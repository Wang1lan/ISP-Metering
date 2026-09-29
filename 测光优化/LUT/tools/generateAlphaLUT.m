function info = generateAlphaLUT()
%GENERATEALPHALUT 离线生成完整 8 bit 亮度地址网格的中心权重表。
% 地址为 256*Lp_q+Lc_q，Lc 变化最快，首项 (0,0) 特殊取 Wc。

    % USER PARAMETERS BEGIN
    rho1 = 0.5;
    rho2 = 0.9;
    rho3 = 1.1;
    rho4 = 1.5;
    alphaMin = 0.25;
    Wc = 0.5;
    alphaMax = 0.75;
    LpMin = 1;
    outputMode = 'both';          % 'float'、'fixed' 或 'both'
    fracBits = 12;                % 1~30
    outputDir = fullfile(fileparts(mfilename('fullpath')), '..');
    % USER PARAMETERS END

    parameters = struct('lutType', 'Alpha', 'inputBits', 8, ...
        'LcLevels', 256, 'LpLevels', 256, ...
        'rho1', rho1, 'rho2', rho2, 'rho3', rho3, 'rho4', rho4, ...
        'alphaMin', alphaMin, 'Wc', Wc, 'alphaMax', alphaMax, 'LpMin', LpMin);
    positiveNames = {'rho1', 'rho2', 'rho3', 'rho4', 'LpMin'};
    for k = 1:numel(positiveNames)
        name = positiveNames{k};
        validateattributes(parameters.(name), {'numeric'}, ...
            {'real', 'finite', 'scalar', 'positive'}, mfilename, name);
        parameters.(name) = double(parameters.(name));
    end
    weightNames = {'alphaMin', 'Wc', 'alphaMax'};
    for k = 1:numel(weightNames)
        name = weightNames{k};
        validateattributes(parameters.(name), {'numeric'}, ...
            {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, name);
        parameters.(name) = double(parameters.(name));
    end
    p = parameters;
    assert(p.rho1 < p.rho2 && p.rho2 <= 1 && 1 <= p.rho3 && ...
        p.rho3 < p.rho4 && p.rho2 < p.rho3, ...
        'generateAlphaLUT:InvalidThresholds', ...
        '必须满足 0 < rho1 < rho2 <= 1 <= rho3 < rho4，且 rho2 < rho3。');
    assert(p.alphaMin <= p.Wc && p.Wc <= p.alphaMax, ...
        'generateAlphaLUT:InvalidWeights', ...
        '必须满足 0 <= alphaMin <= Wc <= alphaMax <= 1。');

    lutFloat = zeros(65536, 1);
    for Lp_q = 0:255
        for Lc_q = 0:255
            if Lc_q == 0 && Lp_q == 0
                alpha = p.Wc;
            else
                rho = Lc_q / max(Lp_q, p.LpMin);
                if rho <= p.rho1
                    alpha = p.alphaMin;
                elseif rho < p.rho2
                    alpha = p.alphaMin + (p.Wc - p.alphaMin) * ...
                        (rho - p.rho1) / (p.rho2 - p.rho1);
                elseif rho <= p.rho3
                    alpha = p.Wc;
                elseif rho < p.rho4
                    alpha = p.Wc + (p.alphaMax - p.Wc) * ...
                        (rho - p.rho3) / (p.rho4 - p.rho3);
                else
                    alpha = p.alphaMax;
                end
            end
            addr = 256 * Lp_q + Lc_q;
            lutFloat(addr + 1) = alpha;
        end
    end
    parameters.addressFormula = '256*Lp_q+Lc_q';
    parameters.addressOrder = 'LcFastest';
    parameters.blackFrameRule = 'Lc==0&&Lp==0:Wc';
    info = exportMeteringLUT(lutFloat, outputDir, ...
        'LUT_Alpha_L8', outputMode, fracBits, parameters);
end
