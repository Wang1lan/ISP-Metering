function [APMvalue, smY, pieceave] = comen_APM_fx(image, validmatrixin, peak_quantity)

[img_signed, img_wl, img_fl] = deal(1,1+8,0);

F = fimath('RoundingMethod', 'Floor',...
            'OverflowAction', 'Saturate',...
            'ProductMode', 'FullPrecision',...
            'SumMode', 'FullPrecision');
        
F1 = fimath('RoundingMethod', 'Nearest',...
            'OverflowAction', 'Saturate',...
            'ProductMode', 'FullPrecision',...
            'SumMode', 'FullPrecision');
T_img = numerictype('Signed',img_signed,...
                    'WordLength',img_wl,...
                    'FractionLength',img_fl);


image = double(image);
[M,N,D] = size(image);
rn = fix(M/16);
cn = fix(N/16);

image = fi(double(image), 1, 1+8+2, 0, F);
pave = fi(zeros(rn,cn), T_img, F);
smY = fi(zeros(rn,cn), 1, 20, 0, F);

for i = 1:rn
    for j = 1:cn
        smt = fi(0, 1, 1+16+2, 0, F);
        mt = image(16*(i-1)+1 : 16*i, 16*(j-1)+1 : 16*j);
        for h = 1:16
            for g = 1:16
                smt = fi(double(smt) + double(mt(h,g)), 1, 1+16+2, 0, F);
            end
        end
        smY(i,j) = double(smt);
        pave(i,j) = fi(double(smt)/2^10, T_img, F);
    end
end

smY = smY';
pave = double(pave);
pavetemp = pave';
pieceave = pavetemp(:);
% validmatrix = validmatrixin(1:rn*cn);

%% only peak mode
piece = pieceave .* 1;
p = zeros(1,256);
summ = zeros(1,256);
len = length(piece);
for i = 1:len
    j = piece(i)+1;
    p(1,j) = p(1,j) + 1;
end


T = p(256);
SV = fi(255*p(256), 1, 22, 0, F);
summ(256) = SV;
for i = 255:-1:1
    if p(256) >= peak_quantity
        break;
    else
        T = T + p(1,i);
        if T < peak_quantity
            SV = fi(double(SV) + (i-1)*double(p(1,i)), 1, 22, 0, F);
            summ(i) = SV;
        else
            temp = T - peak_quantity;
            SV = fi(double(SV) + (i-1)*(p(1,i) - temp), 1, 22, 0, F);
            summ(i) = SV;
            break;
        end
    end
end
if p(1,256) >= peak_quantity
    APMvalue = fi(255, T_img, F);
else
    APMvaluetemp = fi(double(SV)/peak_quantity, T_img, F1);
    APMvalue = fi(double(APMvaluetemp), T_img, F);
end
end







