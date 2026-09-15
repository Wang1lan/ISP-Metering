function comen_APM_funmex(M,N,D)

rn = fix(M/16);
cn = fix(N/16);

u = coder.typeof(double(0), [M,N]);
k = coder.typeof(double(0), [rn*cn, 1]);
l = coder.typeof(double(0));

fiaccel comen_APM_fx -args {u,k,l} -o compiled\comen_APM_fxmex
disp('----Accel comen_APM_fx succeed----');
