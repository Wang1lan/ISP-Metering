function [value, debug] = divideByReciprocalLUT(numerator, denominator, luts)
%DIVIDEBYRECIPROCALLUT 共用已初始化倒数表计算 N/D，返回未限幅的 double 商。
% N>=0、D>0；地址为零基，均值亮度限幅由调用者完成。

    [fraction, binaryExponent] = log2(double(denominator));
    debug.normalizedDenominator = pow2(fraction, 1);
    debug.exponent = binaryExponent - 1;
    count = luts.meta.reciprocal.length;
    debug.address = min(count - 1, max(0, ...
        floor((debug.normalizedDenominator - 1) * count)));
    debug.reciprocal = luts.reciprocal(debug.address + 1);
    value = pow2(double(numerator) * debug.reciprocal, -debug.exponent);
end
