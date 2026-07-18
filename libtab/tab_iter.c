/*
 * tab_iter — iteration over rows.
 *
 * Two flavours, same TabIter struct:
 *
 *   tab_iter(t)             — unfiltered scan, every row in source order.
 *   tab_search(t, col, val) — same scan, only rows whose `col` cell
 *                             equals `val`.  Empty cells never match a
 *                             non-empty value.
 *
 * Search is a linear walk because we have one map (the row-hash map)
 * and it's keyed by row identity, not column.  This is the deliberate
 * shape: a substrate for tables, not a relational engine.
 *
 * The TabRow* returned by tab_iter_next points directly into
 * t->rows[] and is owned by the Tab.  Closing the iterator does not
 * invalidate it; only tab_close does.  Iterators are pure cursors.
 */

#include "tab_internal.h"

TabIter *
tab_iter(Tab *t)
{
	TabIter *it;

	tab_clearerror();
	if(t == nil){
		tab_seterror("tab_iter: nil Tab");
		return nil;
	}
	it = mallocz(sizeof *it, 1);
	if(it == nil){
		tab_seterror("tab_iter: out of memory");
		return nil;
	}
	it->t = t;
	it->idx = 0;
	it->col = nil;
	it->value = nil;
	return it;
}

TabRow *
tab_iter_next(TabIter *it)
{
	const char *cell;
	TabRow *r;

	if(it == nil)
		return nil;
	for(; it->idx < it->t->nrows; it->idx++){
		r = it->t->rows[it->idx];
		if(it->col != nil){
			cell = tab_row_cell(r->chain, it->col);
			if(cell == nil || strcmp(cell, it->value) != 0)
				continue;
		}
		it->idx++;
		return r;
	}
	return nil;
}

void
tab_iter_close(TabIter *it)
{
	if(it == nil)
		return;
	free(it->col);
	free(it->value);
	free(it);
}
