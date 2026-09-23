function [output1,output2] = feak_list(input,ration)
%output1:像素总和
%output2:个数
p = zeros(1,256);                               % 初始化直方图输出
len = length(input);                            % 输入数据总长度
Peak_quantity = fix(len * (ration/ 100));       % 总长度其中一部分的长度
for i = 1:len                                   % 1:8040(图像块的大小为16*16)
     j = input(i)+1;                            % 1:256（像素值的取值范围为：1~256）
     p(1,j) = p(1,j) +1;                        % 得到了所有图像块的直方图 
end

T = p(256);                                     % T表示图像块均值为255的个数
SV = 255*T;                                     % 像素为255的个数乘以255
for i = 255:-1:1
     if p(256) >= Peak_quantity                 % 当像素值位255的个数大于len*ration
         break;                                 % 跳出
     else
         T = T + p(1,i);                        % 否则，255像素值的个数加上254像素的个数值
         if T < Peak_quantity                   % 如果T小于128
             SV = double(SV) + (i-1)*double(p(1,i));  %(i-1)*double(p(1,i)表示i位置的个数乘以i位置的像素值
         else                                   % 如果T大于阈值
             temp = T - Peak_quantity;          % temp = T - 阈值
             SV = double(SV) + (i-1)*(p(1,i)-temp);   %如果个数大于128，则将多余的像素值减去
             break;
         end
     end
end

if p(1,256) >= Peak_quantity                    % 如果像素值位255的个数大于128
    output1 = Peak_quantity * 255;
    output2 = Peak_quantity;                    % 输出结果为255
else                                            % 如果像素值位255的个数小于128
    output1 = SV;
    output2 = Peak_quantity;
end

end