
%let dic = motherfolder;
%let input = datafolder.;

libname ldata "&dic.";	

%macro import_data(data = );
	proc import out = raw_&data. datafile = "&input/&data..csv" dbms = csv replace;
	getnames = yes;
	run;
%mend;

%import_data(data = month_map);

%import_data(data = sos);

%import_data(data = cooler_detail);
%import_data(data = cooler);

%import_data(data = store);

proc sort data = raw_sos; by store month;
proc sort data = raw_cooler_detail; by store month;
proc sort data = raw_store; by store month;
proc sort data = raw_cooler; by store month;
run;

%import_data(data = month_map);

* merge all NSO data;

data p_nso;
	merge raw_store raw_sos raw_cooler_detail raw_cooler;
	by store month;
	if if_ksf600 = . then if_ksf600 = 0;
	if if_ksf_600ml = . then if_ksf_600ml = 0;
	if if_ksf_cooler = . then if_ksf_cooler = 0;
	if if_ksf600ml = . then if_ksf600ml = 0;
	if_ksf = if_ksf600 + if_ksf_600ml + if_ksf_cooler + if_ksf600ml;
	drop if_ksf600 if_ksf_600ml if_ksf_cooler if_ksf600ml;
	if q23 = . then q23 = 0;
	if q24 = . then q24 = 0;
	if q25 = . then q25 = 0;
	run;

proc sort data = p_nso; by month;
proc sort data= raw_month_map; by month;

data p_nso;
	merge raw_month_map p_nso(in = a);
	by month;
	if a;
	run;

*merge nso data with store information;

proc import out = raw_storemst datafile = "&input.\storemaster.xls" dbms = excel replace;
getnames = yes;
sheet = "total";
run;

proc sort data = p_nso; by store per; run;
proc sort data = raw_storemst; by store per; run;

data p_nso;
	merge p_nso(in = a) raw_storemst(in = b keep = storecode store per);
	by store per;
	if a and b;
	run;

*Finalized NSO;

proc datasets lib=work nolist;
     delete Raw_:;
quit;

/********************************************************************************************/
/*******************Load Sales Data**********************************************************/
/********************************************************************************************/

/*******************CSD**********************************************************/

* import sales data;

%import_data(data = sales_csd);

data raw_sales_csd;
	set raw_sales_csd;
	if salesunit > 0;
	rename periodcode = per x_factor = xf z_factor = zf;
	value = price * salesunit;
	if itemcode = dealcode then bundle = 0;
	else bundle = 1;
	itemcode = dealcode;
	drop sourceid price;
	run;

*merge item master;

%import_data(data = item_csd);

data raw_item_csd;
	set raw_item_csd;
	packsize = multipack * quantity;
	if quantity > 600 then pack = "ms";
	else pack = "ss";
	run;

proc sort data = raw_sales_csd; by itemcode;
proc sort data = raw_item_csd; by itemcode;
data raw_sales_csd;
	merge raw_sales_csd(in = a) raw_item_csd;
	by itemcode;
	if a;
	run;

data raw_sales_csd raw_sales_csd_backup;
	set raw_sales_csd;
	if packsize NE .;
	volume = salesunit * packsize;
	price = value / volume;
	keep per cellcode storecode itemcode xf zf value bundle brand_desc pack volume price;
	run;

proc means data = raw_sales_csd nway noprint;
	class per storecode brand_desc pack;
	var value bundle volume;
	output out = raw_sales_csd(drop = _:) sum(value) = value sum(volume) = volume max(bundle) = bundle;
	run;

data raw_sales_csd;
	set raw_sales_csd;
	price = value / volume;
	run;

*merge store master;

proc import out = raw_storemst datafile = "&input.\storemaster.xls" dbms = excel replace;
getnames = yes;
sheet = "total";
run;

*merge nso data;

proc sort data = p_nso; by storecode per;
proc sort data = raw_sales_csd; by storecode per;
run;

data p_sales_csd;
	merge raw_sales_csd(in = a) p_nso;
	by storecode per;
	if a;
	if if_coke_cooler NE .;
	run;

* keep full observations stores;

data raw_store_full_csd;
	set p_sales_csd;
	keep storecode per;
	run;

proc sort data = raw_store_full_csd nodup; by storecode per; run;

proc means data = raw_store_full_csd nway noprint;
	class storecode;
	var per;
	output out = raw_store_full_csd(drop = _:) mean = n = obs;
	run;

data raw_store_full_csd;
	set raw_store_full_csd;
	if obs = 8;
	fullstorecode = storecode;
	keep storecode fullstorecode;
run;	

	*build template for final merge;

%import_data(data = month_map);

data raw_month_map;
	set raw_month_map;
	syntax = "data temp; set raw_store_full_csd; per = "||per||";run; data raw_map_csd; set raw_map_csd temp; run;";
	run;

data _null_;
	set raw_month_map end = eof;
	if _n_ = 1 then do;
		call execute ('data Raw_map_csd; run;');
	end;
	call execute (syntax);
	if eof then do;
		call execute ('data raw_map_csd; set raw_map_csd; if per = . then delete; run;');
	end;
	run;

	*end of template building;

proc sort data = raw_map_csd; by storecode per; run;
proc sort data = p_sales_csd; by storecode per; run;

data temp;
	merge raw_map_csd(in = a drop = fullstorecode) raw_sales_csd;
	by storecode per;
	if a;
	run;

*Generate some other variables for model;

proc sql;
	create table raw_sales_csd_cat as
	select storecode, per, sum(volume) as catvol, sum(value) as catval
	from temp
	group by storecode, per;
	quit;

proc means data = temp nway noprint;
	class per;
	var volume value;
	output out = raw_sales_csd_ss(drop = _:) median(volume) = ssvol median(value) = ssval;
	run;

proc sort data = raw_sales_csd_ss; by per;
proc sort data = raw_sales_csd_cat; by per;
data p_other_csd;
	merge raw_sales_csd_cat(in = a) raw_sales_csd_ss;
	by per;
	if a;
	run;

proc sql;
	create table raw_sales_csd_store as
	select storecode, mean(volume) as storevol, sum(value) as storeval
	from temp
	group by storecode;
	quit;

proc sort data = raw_sales_csd_store; by storecode; run;
proc sort data = p_other_csd; by storecode; run;

data p_other_csd;
	merge p_other_csd(in = a) raw_sales_csd_store;
	by storecode;
	if a;
	run;

*merge all variables;

data p_coke_ss;
	set temp;
	if brand_desc = "Coca-Co" and pack = "ss";
	rename value = coke_ss_val volume = coke_ss_vol bundle = coke_ss_bundle price = coke_ss_avp;
	drop brand_desc pack;
	run;

data p_coke_ms;
	set temp;
	if brand_desc = "Coca-Co" and pack = "ms";
	rename value = coke_ms_val volume = coke_ms_vol bundle = coke_ms_bundle price = coke_ms_avp;
	drop brand_desc pack;
	run;

data p_sprite_ss;
	set temp;
	if brand_desc = "Sprite" and pack = "ss";
	rename value = sprite_ss_val volume = sprite_ss_vol bundle = sprite_ss_bundle price = sprite_ss_avp;
	drop brand_desc pack;
	run;

data p_sprite_ms;
	set temp;
	if brand_desc = "Sprite" and pack = "ms";
	rename value = sprite_ms_val volume = sprite_ms_vol bundle = sprite_ms_bundle price = sprite_ms_avp;
	drop brand_desc pack;
	run;

proc sort data = raw_map_csd; by storecode per;
proc sort data = p_coke_ss; by storecode per;
proc sort data = p_coke_ms; by storecode per;
proc sort data = p_sprite_ss; by storecode per;
proc sort data = p_sprite_ms; by storecode per;
proc sort data = p_other_csd; by storecode per;
proc sort data = p_nso; by storecode per;
proc sort data = raw_storemst; by storecode per;
run;

data p_sales_csd;
	merge raw_map_csd(in = a) p_coke_ss p_coke_ms p_sprite_ss p_sprite_ms p_nso raw_storemst p_other_csd;
	by storecode per;
	if a;
	rename catvol = csdvol catval = csdval ssvol = csdssvol ssval = csdssval storevol = csdstorevol storeval = csdstoreval;
	run;

data p_sales_csd_backup;
	merge raw_map_csd(in = a) temp p_nso raw_storemst p_other_csd;
	by storecode per;
	if a;
	run;

proc datasets lib=work nolist;
     delete Raw_: temp;
quit;

/*******************JUICE**********************************************************/

%import_data(data = sales_juice);

data raw_sales_juice;
	set raw_sales_juice;
	if salesunit > 0;
	rename periodcode = per x_factor = xf z_factor = zf;
	value = price * salesunit;
	if itemcode = dealcode then bundle = 0;
	else bundle = 1;
	itemcode = dealcode;
	drop sourceid price;
	run;

*merge item master;

%import_data(data = item_juice);

data raw_item_juice;
	set raw_item_juice;
	packsize = multipack * quantity;
	if quantity > 600 then pack = "ms";
	else pack = "ss";
	run;

proc sort data = raw_sales_juice; by itemcode;
proc sort data = raw_item_juice; by itemcode;
data raw_sales_juice;
	merge raw_sales_juice(in = a) raw_item_juice;
	by itemcode;
	if a;
	run;

data raw_sales_juice raw_sales_juice_backup;
	set raw_sales_juice;
	if packsize NE .;
	volume = salesunit * packsize;
	price = value / volume;
	keep per cellcode storecode itemcode xf zf value bundle brand_desc pack volume price;
	run;

proc means data = raw_sales_juice nway noprint;
	class per storecode brand_desc pack;
	var value bundle volume;
	output out = raw_sales_juice(drop = _:) sum(value) = value sum(volume) = volume max(bundle) = bundle;
	run;

data raw_sales_juice;
	set raw_sales_juice;
	price = value / volume;
	run;

*merge store master;

proc import out = raw_storemst datafile = "&input.\storemaster.xls" dbms = excel replace;
getnames = yes;
sheet = "total";
run;

*merge nso data;

proc sort data = p_nso; by storecode per;
proc sort data = raw_sales_juice; by storecode per;
run;

data p_sales_juice;
	merge raw_sales_juice(in = a) p_nso;
	by storecode per;
	if a;
	if if_coke_cooler NE .;
	run;

* keep full observations stores;

data raw_store_full_juice;
	set p_sales_juice;
	keep storecode per;
	run;

proc sort data = raw_store_full_juice nodup; by storecode per; run;

proc means data = raw_store_full_juice nway noprint;
	class storecode;
	var per;
	output out = raw_store_full_juice(drop = _:) mean = n = obs;
	run;

data raw_store_full_juice;
	set raw_store_full_juice;
	if obs = 8;
	fullstorecode = storecode;
	keep storecode fullstorecode;
run;	

	*build template for final merge;

%import_data(data = month_map);

data raw_month_map;
	set raw_month_map;
	syntax = "data temp; set raw_store_full_juice; per = "||per||";run; data raw_map_juice; set raw_map_juice temp; run;";
	run;

data _null_;
	set raw_month_map end = eof;
	if _n_ = 1 then do;
		call execute ('data Raw_map_juice; run;');
	end;
	call execute (syntax);
	if eof then do;
		call execute ('data raw_map_juice; set raw_map_juice; if per = . then delete; run;');
	end;
	run;

	*end of template building;

proc sort data = raw_map_juice; by storecode per; run;
proc sort data = p_sales_juice; by storecode per; run;

data temp;
	merge raw_map_juice(in = a drop = fullstorecode) raw_sales_juice;
	by storecode per;
	if a;
	run;

*Generate some other variables for model;

proc sql;
	create table raw_sales_juice_cat as
	select storecode, per, sum(volume) as catvol, sum(value) as catval
	from temp
	group by storecode, per;
	quit;

proc means data = temp nway noprint;
	class per;
	var volume value;
	output out = raw_sales_juice_ss(drop = _:) median(volume) = ssvol median(value) = ssval;
	run;

proc sort data = raw_sales_juice_ss; by per;
proc sort data = raw_sales_juice_cat; by per;
data p_other_juice;
	merge raw_sales_juice_cat(in = a) raw_sales_juice_ss;
	by per;
	if a;
	run;

proc sql;
	create table raw_sales_juice_store as
	select storecode, mean(volume) as storevol, sum(value) as storeval
	from temp
	group by storecode;
	quit;

proc sort data = raw_sales_juice_store; by storecode; run;
proc sort data = p_other_juice; by storecode; run;

data p_other_juice;
	merge p_other_juice(in = a) raw_sales_juice_store;
	by storecode;
	if a;
	run;

*merge modelfile;

data p_minute_ss;
	set temp;
	if brand_desc = "Minute" and pack = "ss";
	rename value = minute_ss_val volume = minute_ss_vol bundle = minute_ss_bundle price = minute_ss_avp;
	drop brand_desc pack;
	run;

data p_minute_ms;
	set temp;
	if brand_desc = "Minute" and pack = "ms";
	rename value = minute_ms_val volume = minute_ms_vol bundle = minute_ms_bundle price = minute_ms_avp;
	drop brand_desc pack;
	run;

proc sort data = raw_map_juice; by storecode per;
proc sort data = p_minute_ss; by storecode per;
proc sort data = p_minute_ms; by storecode per;
proc sort data = p_other_juice; by storecode per;
proc sort data = p_nso; by storecode per;
proc sort data = raw_storemst; by storecode per;
run;

data p_sales_juice;
	merge raw_map_juice(in = a) p_minute_ss p_minute_ms p_nso raw_storemst p_other_juice;
	by storecode per;
	if a;
	rename catvol = juicevol catval = juiceval ssvol = juicessvol ssval = juicessval storevol = juicestorevol storeval = juicestoreval;
	run;

data p_sales_juice_backup;
	merge raw_map_juice(in = a) temp p_nso raw_storemst p_other_juice;
	by storecode per;
	if a;
	run;

proc datasets lib=work nolist;
     delete Raw_: temp;
quit;

/********************************************************************************************/
/*******************End of Data Processing***************************************************/
/********************************************************************************************/

data p_other_csd;
	set p_other_csd;
	rename catvol = csdvol catval = csdval ssvol = csdssvol ssval = csdssval storevol = csdstorevol storeval = csdstoreval;
	run;
data p_other_juice;
	set p_other_juice;
	rename catvol = juicevol catval = juiceval ssvol = juicessvol ssval = juicessval storevol = juicestorevol storeval = juicestoreval;
	run;

data raw_store_full_total;
	set p_sales_csd p_sales_juice;
	keep storecode per;
	run;

proc means data = raw_store_full_total nway noprint;
	class storecode;
	output out = raw_store_full_total(drop = _:) n = obs;
	run;

data raw_store_full_total;
	set raw_store_full_total;
	if obs = 16;
	drop obs;
	run;

%import_data(data = month_map);

data raw_month_map;
	set raw_month_map;
	syntax = "data temp; set raw_store_full_total; per = "||per||";run; data raw_map_total; set raw_map_total temp; run;";
	run;

data _null_;
	set raw_month_map end = eof;
	if _n_ = 1 then do;
		call execute ('data Raw_map_total; run;');
	end;
	call execute (syntax);
	if eof then do;
		call execute ('data raw_map_total; set raw_map_total; if per = . then delete; run;');
	end;
	run;

proc sort data = raw_map_total; by storecode per; run;

proc import out = raw_storemst datafile = "&input.\storemaster.xls" dbms = excel replace;
getnames = yes;
sheet = "total";
run;

data p_sales;
	merge raw_map_total( in = a) p_coke_ss p_coke_ms p_sprite_ss p_sprite_ms p_minute_ss p_minute_ms p_other_csd p_other_juice p_nso;
	if a;
	by storecode per;
	run;

proc sort data = raw_storemst; by storecode per; run;

data p_sales;
	merge p_sales(in = ifa) raw_storemst;
	if ifa;
	by storecode per;
	run;

data ldata.p_sales;
	set p_sales;
	run;

proc export data = p_sales outfile = "&dic./sales.csv" dbms = csv replace;
run;
	


%macro export_ldata(data =);
	data ldata.&data.;
		set p_&data.;
		run;
%mend export_ldata;

%macro export_csv(data =);
	proc export data = p_&data. outfile = "&dic./&data..csv" dbms = csv replace; run;
%mend export_csv;
