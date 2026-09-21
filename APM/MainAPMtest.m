%% Main AWB test
addpath('compiled');

imgin = double(imread('C:\Users\mhcheng\Desktop\Kodak\kodim21.png'));
imgin = imresize(imgin, [1080,1920]);
imT = double(uint8(imgin));
[M,N,D] = size(imT);
im = imT / 2^8 * 2^10;

%%
fid = fopen('D:\MatlabCode\APM\check\input\r.txt', 'wt');
B = uint16(im(:,:,1));
fprintf(fid, '%04X\n', B');
fclose(fid);
fid = fopen('D:\MatlabCode\APM\check\input\g.txt', 'wt');
B = uint16(im(:,:,2));
fprintf(fid, '%04X\n', B');
fclose(fid);
fid = fopen('D:\MatlabCode\APM\check\input\b.txt', 'wt');
B = uint16(im(:,:,3));
fprintf(fid, '%04X\n', B');
fclose(fid);
%%

rn = fix(M/16);
cn = fix(N/16);
validmatrixin = ones(rn*cn, 1);
peak_quantity = 1024;

%% ft
% Imgout_ft = comen_CCM_ft(im, CCM);

img = zeros(M,N);
%% fx
for i = 1:M
    for j = 1:N
        img(i,j) = max([im(i,j,1), im(i,j,2), im(i,j,3)]);
    end
end
APM_funmex(M,N,D);
[Imgout_fx, temp, temp2] = APM_fxmex(img, validmatrixin, peak_quantity);



%% 
% err = abs(Imgout_ft - double(Imgout_fx)) * 2^8;
% figure,hist(err)
% 
% r = err(:,:,1);
% g = err(:,:,2);
% b = err(:,:,3);

