function [fixture, cleanup] = meteringLUTTestFixture(projectDir, changes, blockSize)
%METERINGLUTTESTFIXTURE 在自有临时目录复制并运行无参离线生成器。
% changes.R/alpha/lambda 的字段值是 MATLAB 表达式文本，例如 '8'、'''ratio'''。
% 仅替换 USER PARAMETERS BEGIN/END 内唯一的一条赋值，不改变生成器接口。
% blockSize 省略时复制正式 FOV；指定时创建 8x16 的非对称合成 FOV。
    if nargin < 2, changes = struct(); end
    if nargin < 3, blockSize = []; end
    parent = tempdir;
    folder = tempname(parent);
    assert(~isfolder(folder), 'meteringLUTTestFixture:AlreadyExists', ...
        '临时目录已经存在。');
    mkdir(folder);
    cleanup = onCleanup(@() removeOwned(folder, parent));
    toolsDir = fullfile(folder, 'LUT', 'tools');
    mkdir(fullfile(folder, 'LUT'));
    copyfile(fullfile(projectDir, 'LUT', 'tools'), toolsDir);
    mkdir(fullfile(folder, 'float'));
    helpers = {'loadFovBlockMask.m', 'meteringFileSHA256.m', 'readMeteringColumn.m'};
    for k = 1:numel(helpers)
        copyfile(fullfile(projectDir, 'float', helpers{k}), fullfile(folder, 'float'));
    end
    weights = fullfile(folder, 'weights');
    mkdir(weights);
    if isempty(blockSize)
        fixture.imageSize = [1080, 1920];
        fixture.weightFile = fullfile(weights, 'fov.txt');
        copyfile(fullfile(projectDir, '权重配置文件', ...
            '圆形有效视场权重_16×16.txt'), fixture.weightFile);
    else
        fixture.imageSize = [8 * blockSize + 3, 16 * blockSize + 5];
        fixture.weightFile = fullfile(weights, 'fov.txt');
        mask = true(8, 16);
        mask(1, 2) = false; mask(3, 1:4) = false; mask(8, 16) = false;
        writeColumn(fixture.weightFile, reshape(double(mask.'), [], 1));
        fixture.expectedMask = mask;
        changes.R.blockSize = sprintf('%d', blockSize);
        changes.lambda.blockSize = sprintf('%d', blockSize);
    end
    changes.lambda.imageSize = mat2str(fixture.imageSize);
    if ~isfield(changes.lambda, 'fovFile')
        changes.lambda.fovFile = quote(fixture.weightFile);
    end
    names = {'R', 'alpha', 'lambda'};
    funcs = {'generateReliabilityLUT', 'generateAlphaLUT', 'generateFusionLUT'};
    for k = 1:numel(names)
        name = names{k};
        changes.(name).outputDir = quote(fullfile(folder, 'LUT'));
        file = fullfile(toolsDir, [funcs{k}, '.m']);
        patchParameters(file, changes.(name));
    end
    oldPath = path;
    pathCleanup = onCleanup(@() restorePath(oldPath));
    addpath(fullfile(folder, 'float'), toolsDir, '-begin');
    clear generateReliabilityLUT generateAlphaLUT generateFusionLUT exportMeteringLUT
    for k = 1:numel(funcs)
        selected = java.io.File(which(funcs{k}));
        expected = java.io.File(fullfile(toolsDir, [funcs{k}, '.m']));
        assert(strcmpi(char(selected.getCanonicalPath()), char(expected.getCanonicalPath())), ...
            'meteringLUTTestFixture:GeneratorPath', ...
            '%s 必须解析到当前隔离副本。', funcs{k});
    end
    fixture.info.R = generateReliabilityLUT();
    fixture.info.alpha = generateAlphaLUT();
    fixture.info.lambda = generateFusionLUT();
    fixture.root = folder;
    fixture.cfg = createMeteringConfig();
    for k = 1:numel(names)
        fixture.cfg.lutManifests.(names{k}) = fixture.info.(names{k}).manifestFile;
    end
end

function patchParameters(file, values)
    source = fileread(file);
    first = strfind(source, 'USER PARAMETERS BEGIN');
    last = strfind(source, 'USER PARAMETERS END');
    assert(numel(first) == 1 && numel(last) == 1 && first < last, ...
        'meteringLUTTestFixture:ParameterMarkers', '参数区标记必须各出现一次。');
    before = source(1:first-1);
    region = source(first:last-1);
    after = source(last:end);
    names = fieldnames(values);
    for k = 1:numel(names)
        name = names{k};
        expression = ['(?m)^([ \t]*', regexptranslate('escape', name), ...
            '[ \t]*=[ \t]*)[^\r\n;]*;'];
        [starts, ends, tokens] = regexp(region, expression, 'start', 'end', 'tokens');
        assert(numel(starts) == 1, 'meteringLUTTestFixture:AssignmentCount', ...
            '%s 中参数 %s 的赋值必须恰好出现一次。', file, name);
        region = [region(1:starts-1), tokens{1}{1}, values.(name), ';', ...
            region(ends+1:end)];
    end
    fid = fopen(file, 'wt');
    assert(fid >= 0, 'meteringLUTTestFixture:WriteFailed', '无法写入测试生成器。');
    done = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', [before, region, after]);
end

function value = quote(value)
    value = ['''', strrep(value, '''', ''''''), ''''];
end

function writeColumn(file, values)
    fid = fopen(file, 'wt');
    assert(fid >= 0);
    done = onCleanup(@() fclose(fid));
    fprintf(fid, '%.17g\n', values);
end

function restorePath(oldPath)
    clear generateReliabilityLUT generateAlphaLUT generateFusionLUT exportMeteringLUT
    path(oldPath);
end

function removeOwned(folder, parent)
    file = java.io.File(folder); root = java.io.File(parent);
    absolute = char(file.getCanonicalPath());
    base = char(root.getCanonicalPath());
    assert(startsWith(absolute, [base, filesep], 'IgnoreCase', true) && ...
        ~strcmpi(absolute, base), 'meteringLUTTestFixture:UnsafeCleanup', ...
        '只能清理当前测试在临时目录内创建的目录。');
    % 异常退出时 onCleanup 对象的析构次序不保证路径先恢复。
    % 先移除本夹具路径，避免 rmdir 触发 MATLAB 自动删除失效路径的警告。
    entries = strsplit(path, pathsep);
    owned = startsWith(entries, [absolute, filesep], 'IgnoreCase', true) | strcmpi(entries, absolute);
    if any(owned), rmpath(entries{owned}); end
    if isfolder(absolute), rmdir(absolute, 's'); end
end
