
%let modelfile = target_sku;

data model_&modelfile.;
	set ldata.&modelfile.;
	if Q22 > 0 then if22 = storevol;
	else if22 =0 ;
	if volume = . then volume = 0;
	if value = . then value = 0;
	if price = . then price = 0;
	exist = B7_ss_exist * storevol;
	face = B7_ss_face * storevol;
	cface = B7_ss_cface * storevol;
	pexist = B7_ss_pexist * storevol;
	run;

%let dep_var = volume;
%let varlist = if22 pexist exist storevol ssvol KEY B C TGTS;

proc reg data = model_&modelfile. outest = out_&modelfile._coef(keep = intercept &varlist.) rsquare;
	test: model &dep_var. = &varlist.
	/dw vif adjrsq;
	output out = out_&modelfile._decomp(keep = storecode per &dep_var. &varlist. pred residual) p = pred r = residual;
	ods output;
quit;

proc transpose data = out_&modelfile._coef out = out_&modelfile._coef; run;
/*
data out_&modelfile._coef;
	set out_&modelfile._coef;
	length syntax $ 200 ;
	if _n_ =1 then do;
		syntax = ''||_name_||'=1*'||col1||';';
	end;
	if _n_ >1 then do;
		syntax = ''||_name_||'='||_name_||'*'||col1||';';
	end;
	run;*/
data _null_;
	set out_&modelfile._coef end = eof;
	if _n_ = 1 then do;
		call execute ('data out_&modelfile._decomp; set out_&modelfile._decomp; intercept=1*'||col1||'/pred;');
	end;
	if _n_ > 1 then do;
		call execute (''||_name_||'='||_name_||'*'||col1||'/pred;');
	end;
	if eof then do;
		call execute ('run;');
	end;
	run;

proc means data = out_&modelfile._decomp nway noprint;
	class per;
	var intercept &varlist volume;
	weight pred;
	output out = out_&modelfile._sovc(drop = _:) mean() = ;
	run;

proc print data = out_&modelfile._sovc; run;
