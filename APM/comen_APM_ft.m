function ImgOut = comen_CCM_ft(imgin, ccm)

ImgOut = imgin;

r = imgin(:,:,1);
g = imgin(:,:,2);
b = imgin(:,:,3);

ImgOut(:,:,1) = ccm(1,1) * r + ccm(1,2) * g + ccm(1,3) * b;
ImgOut(:,:,2) = ccm(2,1) * r + ccm(2,2) * g + ccm(2,3) * b;
ImgOut(:,:,3) = ccm(3,1) * r + ccm(3,2) * g + ccm(3,3) * b;

ImgOut(ImgOut < 0) = 0;
ImgOut(ImgOut > 2^0 - 2^(-13)) = 2^0 - 2^(-13);