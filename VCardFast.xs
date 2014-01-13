#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "vparse.h"

// hv_store to array, create if not exists - from XML::Fast 0.11
#define hv_store_aa( hv, kv, kl, sv ) \
	STMT_START { \
		SV **exists; \
		if( ( exists = hv_fetch(hv, kv, kl, 0) ) && SvROK(*exists) && (SvTYPE( SvRV(*exists) ) == SVt_PVAV) ) { \
			AV *av = (AV *) SvRV( *exists ); \
			av_push( av, sv ); \
		} \
		else { \
			AV *av   = newAV(); \
			av_push( av, sv ); \
			(void) hv_store( hv, kv, kl, newRV_noinc( (SV *) av ), 0 ); \
		} \
	} STMT_END


static HV *_card2perl(struct vparse_card *card)
{
    struct vparse_card *sub;
    struct vparse_entry *entry;
    HV *res = newHV();
    HV *prophash = newHV();

    if (card->type) {
	hv_store(res, "type", 4, newSVpv(card->type, 0), 0);
	hv_store(res, "properties", 10, newRV_noinc( (SV *) prophash), 0);
    }

    if (card->objects) {
	AV *objarray = newAV();
	hv_store(res, "objects", 7, newRV_noinc( (SV *) objarray), 0);
	for (sub = card->objects; sub; sub = sub->next) {
	    HV *child = _card2perl(sub);
	    av_push(objarray, newRV_noinc( (SV *) child));
	}
    }

    for (entry = card->properties; entry; entry = entry->next) {
	HV *item = newHV();
	size_t len = strlen(entry->name);

	if (entry->multivalue) {
	    AV *av = newAV();
	    struct vparse_list *list;
	    for (list = entry->v.values; list; list = list->next)
		av_push(av, newSVpv(list->s, 0));
	    hv_store(item, "value", 5, newRV_noinc( (SV *) av), 0);
	}
	else {
	    hv_store(item, "value", 5, newSVpv(entry->v.value, 0), 0);
	}

	if (entry->params) {
	    struct vparse_param *param;
	    HV *prop = newHV();
	    for (param = entry->params; param; param = param->next) {
		if (param->value)
		    hv_store(prop, param->name, strlen(param->name), newSVpv(param->value, 0), 0);
		else
		    hv_store(prop, param->name, strlen(param->name), newSV(0), 0);
	    }
	    hv_store(item, "param", 5, newRV_noinc( (SV *) prop), 0);
	}
	hv_store_aa(prophash, entry->name, len, newRV_noinc( (SV *) item));
    }

    return res;
}

static void _die_error(struct vparse_state *state, int err)
{
    struct vparse_errorpos pos;
    const char *src = state->base;

    vparse_fillpos(state, &pos);
    /* everything points into src now */
    vparse_free(state);

    if (pos.startpos <= 60) {
	int len = pos.errorpos - pos.startpos;
	croak("error %s at line %d char %d: %.*s ---> %.*s <---",
	  vparse_errstr(err), pos.errorline, pos.errorchar,
	  pos.startpos, src, len, src + pos.startpos);
    }
    if (pos.errorpos - pos.startpos < 40) {
	int len = pos.errorpos - pos.startpos;
	croak("error %s at line %d char %d: ... %.*s ---> %.*s <---",
	  vparse_errstr(err), pos.errorline, pos.errorchar,
	  40 - len, src + pos.errorpos - 40,
	  len, src + pos.startpos);
    }
    croak("error %s at line %d char %d: %.*s ... %.*s <--- (started at line %d char %d)",
	  vparse_errstr(err), pos.errorline, pos.errorchar,
	  20, src + pos.startpos,
	  20, src + pos.errorpos - 20,
	  pos.startline, pos.startchar);
}

static struct vparse_list *_get_keys(SV **key)
{
    struct vparse_list *item = NULL;
    struct vparse_list **valp = &item;

    if (SvTYPE(SvRV(*key)) == SVt_PVAV) {
	AV *av = (AV *) SvRV( *key );
	I32 len = 0, avlen = av_len(av) + 1;
	SV **val;
	for (len = 0; len < avlen; len++) {
	    val = av_fetch(av, len, 0);
	    if (SvOK(*val) && SvPOK(*val)) {
		struct vparse_list *item = malloc(sizeof(struct vparse_list));
		item->s = strdup(SvPV_nolen(*val));
		item->next = NULL;
		*valp = item;
		valp = &item->next;
	    }
	}
    }

    return item;
}

MODULE = Text::VCardFast		PACKAGE = Text::VCardFast		

SV*
_vcard2hash(src, conf)
	const char *src;
	HV *conf;
    PROTOTYPE: $$
    CODE:
	HV *hash;
	struct vparse_state parser;
	struct vparse_list *multival = NULL;
	int r;
	SV **key;

	if ((key = hv_fetch(conf, "multival", 8, 0)) && SvTRUE(*key)) {
	    multival = _get_keys(key);
	}

	memset(&parser, 0, sizeof(struct vparse_state));

	parser.base = src;
	parser.multival = multival;

	r = vparse_parse(&parser);

	if (r)
	    _die_error(&parser, r);

	hash = _card2perl(parser.card);
	vparse_free(&parser);

	ST(0) = sv_2mortal(newRV_noinc( (SV *) hash));
	XSRETURN(1);

