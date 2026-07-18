/*
 * tab_get — fetch a cell value by column name.
 *
 * Walks the row's ndb tuple chain looking for a tuple whose `attr`
 * matches `col`.  Returns the cell text verbatim — base64 decoding,
 * unsealing, and signature verification come in later steps once
 * the crypto column types arrive.
 */

#include "tab_internal.h"

const char *
tab_row_cell(Ndbtuple *head, const char *col)
{
	Ndbtuple *t;

	if(head == nil || col == nil)
		return nil;
	for(t = head; t != nil; t = t->entry){
		if(strcmp(t->attr, col) == 0)
			return t->val;
	}
	return nil;
}

const char *
tab_get(TabRow *r, const char *col)
{
	if(r == nil)
		return nil;
	return tab_row_cell(r->chain, col);
}
