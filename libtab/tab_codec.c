/*
 * libtab — base64 URL-safe codec and cell-tag helpers.
 *
 * Typed cells on disk carry a self-describing tag:
 *
 *	<tag_lowercase> ':' <base64-url-safe>
 *
 * The base64 alphabet is RFC 4648 §5 — A-Z a-z 0-9 - _ — chosen so
 * cells can sit inside ndb tuples without quoting and inside paths
 * and URLs without escaping.  '=' padding is permitted on input and
 * emitted on output (the design favours interop over compactness).
 *
 * Untagged cells are plain text and don't pass through this module.
 *
 * Step 3 of #88 — codec only.  Step 4+ wires this to the actual
 * HASHED and SIGNED operations.
 */

#include "tab_internal.h"

static const char b64e[64] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	"abcdefghijklmnopqrstuvwxyz"
	"0123456789-_";

#define B64INV 0xff

static uint8_t b64d_table[256];
static int b64d_inited;

static void
b64d_init(void)
{
	int i;

	if(b64d_inited)
		return;
	for(i = 0; i < 256; i++)
		b64d_table[i] = B64INV;
	for(i = 0; i < 64; i++)
		b64d_table[(uint8_t)b64e[i]] = (uint8_t)i;
	b64d_inited = 1;
}

/* Encode `n` bytes from `in` to a fresh malloc'd NUL-terminated string.
 * Output length is 4 * ceil(n / 3) plus the terminator. */
char *
tab_b64_encode(const uint8_t *in, int n)
{
	int olen, i, o;
	uint32_t triple;
	char *out;

	tab_clearerror();
	if(n < 0){
		tab_seterror("tab_b64_encode: negative length");
		return nil;
	}
	olen = 4 * ((n + 2) / 3);
	out = malloc(olen + 1);
	if(out == nil){
		tab_seterror("tab_b64_encode: out of memory");
		return nil;
	}
	o = 0;
	for(i = 0; i + 2 < n; i += 3){
		triple = ((uint32_t)in[i] << 16)
		       | ((uint32_t)in[i+1] << 8)
		       |  (uint32_t)in[i+2];
		out[o++] = b64e[(triple >> 18) & 0x3f];
		out[o++] = b64e[(triple >> 12) & 0x3f];
		out[o++] = b64e[(triple >>  6) & 0x3f];
		out[o++] = b64e[ triple        & 0x3f];
	}
	if(i < n){
		triple = (uint32_t)in[i] << 16;
		if(i + 1 < n)
			triple |= (uint32_t)in[i+1] << 8;
		out[o++] = b64e[(triple >> 18) & 0x3f];
		out[o++] = b64e[(triple >> 12) & 0x3f];
		if(i + 1 < n)
			out[o++] = b64e[(triple >> 6) & 0x3f];
		else
			out[o++] = '=';
		out[o++] = '=';
	}
	out[o] = 0;
	return out;
}

/* Decode `s` (NUL-terminated) into a fresh malloc'd byte buffer.
 * On success returns the buffer; sets *outlen to its length.
 * Returns nil and sets errstr on malformed input. */
uint8_t *
tab_b64_decode(const char *s, int *outlen)
{
	int slen, olen, i, o, pad;
	uint32_t quad;
	uint8_t v0, v1, v2, v3, *out;

	tab_clearerror();
	b64d_init();

	if(s == nil){
		tab_seterror("tab_b64_decode: nil input");
		return nil;
	}
	slen = strlen(s);
	if((slen & 3) != 0){
		tab_seterror("tab_b64_decode: length %d not a multiple of 4", slen);
		return nil;
	}
	if(slen == 0){
		out = malloc(1);
		if(out == nil){
			tab_seterror("tab_b64_decode: out of memory");
			return nil;
		}
		*outlen = 0;
		return out;
	}
	pad = 0;
	if(s[slen - 1] == '=') pad++;
	if(s[slen - 2] == '=') pad++;
	if(pad > 2){
		tab_seterror("tab_b64_decode: too much padding");
		return nil;
	}
	olen = (slen / 4) * 3 - pad;
	out = malloc(olen > 0 ? olen : 1);
	if(out == nil){
		tab_seterror("tab_b64_decode: out of memory");
		return nil;
	}
	o = 0;
	for(i = 0; i < slen; i += 4){
		v0 = b64d_table[(uint8_t)s[i]];
		v1 = b64d_table[(uint8_t)s[i+1]];
		v2 = (s[i+2] == '=') ? 0 : b64d_table[(uint8_t)s[i+2]];
		v3 = (s[i+3] == '=') ? 0 : b64d_table[(uint8_t)s[i+3]];
		if(v0 == B64INV || v1 == B64INV
		   || (s[i+2] != '=' && v2 == B64INV)
		   || (s[i+3] != '=' && v3 == B64INV)){
			tab_seterror("tab_b64_decode: invalid character at offset %d", i);
			free(out);
			return nil;
		}
		quad = ((uint32_t)v0 << 18) | ((uint32_t)v1 << 12)
		     | ((uint32_t)v2 << 6)  |  (uint32_t)v3;
		if(o < olen)
			out[o++] = (quad >> 16) & 0xff;
		if(o < olen)
			out[o++] = (quad >>  8) & 0xff;
		if(o < olen)
			out[o++] =  quad        & 0xff;
	}
	*outlen = olen;
	return out;
}

/* Schema column types are stored in CAPS (HASHED, SIGNED); cell
 * tags are lowercase (hashed:, signed:).  This pair converts
 * between the two without allocating. */
static int
ascii_to_lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c;
}

/* Match a cell against its expected schema type.  Returns 1 if the
 * cell's leading `<lowercase(type)>:` tag is present, 0 if absent.
 * Used by tab_open to validate every typed cell at load time. */
int
tab_cell_has_tag(const char *cell, const char *coltype)
{
	int i;

	if(cell == nil || coltype == nil)
		return 0;
	for(i = 0; coltype[i] != 0; i++){
		if(cell[i] == 0)
			return 0;
		if(ascii_to_lower((unsigned char)cell[i])
		   != ascii_to_lower((unsigned char)coltype[i]))
			return 0;
	}
	return cell[i] == ':';
}

/* Extract the base64 payload that follows a `<tag>:` prefix.  Returns
 * a freshly-allocated decoded byte buffer; *outlen receives its length.
 * Returns nil on failure (no tag, bad b64, etc.). */
uint8_t *
tab_cell_decode(const char *cell, const char *coltype, int *outlen)
{
	const char *p;

	tab_clearerror();
	if(!tab_cell_has_tag(cell, coltype)){
		tab_seterror("tab_cell_decode: cell missing %q: tag", coltype);
		return nil;
	}
	p = cell + strlen(coltype) + 1;	/* skip "<type>:" */
	return tab_b64_decode(p, outlen);
}

/* Build a tagged cell value: `<lowercase(coltype)>:<base64(in)>`.
 * Returns a malloc'd NUL-terminated string.  Used by the Step 4+
 * write helpers (tab_set_sealed etc.). */
char *
tab_cell_encode(const char *coltype, const uint8_t *in, int n)
{
	char *b64, *out;
	int b64len, taglen, total, i;

	tab_clearerror();
	if(coltype == nil){
		tab_seterror("tab_cell_encode: nil column type");
		return nil;
	}
	b64 = tab_b64_encode(in, n);
	if(b64 == nil)
		return nil;
	b64len = strlen(b64);
	taglen = strlen(coltype);
	total = taglen + 1 + b64len;
	out = malloc(total + 1);
	if(out == nil){
		tab_seterror("tab_cell_encode: out of memory");
		free(b64);
		return nil;
	}
	for(i = 0; i < taglen; i++)
		out[i] = ascii_to_lower((unsigned char)coltype[i]);
	out[taglen] = ':';
	memcpy(out + taglen + 1, b64, b64len);
	out[total] = 0;
	free(b64);
	return out;
}
