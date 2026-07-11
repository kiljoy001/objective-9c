#include "tab_internal.h"

void
o9_tab_discard(Tab *tab)
{
	if(tab != nil)
		tab->dirty = 0;
}
