function [info, cleanup] = reciprocalLUTTestFixture(addrBits, outputMode, fracBits)
%RECIPROCALLUTTESTFIXTURE 在自有临时副本运行倒数生成器，不修改交付表。
    if nargin < 2, outputMode = 'both'; end
    if nargin < 3, fracBits = 18; end
    projectDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    parent = tempdir;
    folder = tempname(parent);
    mkdir(folder);
    cleanup = onCleanup(@() removeOwned(folder, parent));
    toolsDir = fullfile(folder, 'LUT', 'tools');
    mkdir(toolsDir);
    mkdir(fullfile(folder, 'float'));
    for name = {'generateReciprocalLUT.m', 'exportMeteringLUT.m'}
        copyfile(fullfile(projectDir, 'LUT', 'tools', name{1}), toolsDir);
    end
    copyfile(fullfile(projectDir, 'float', 'meteringFileSHA256.m'), fullfile(folder, 'float'));
    file = fullfile(toolsDir, 'generateReciprocalLUT.m');
    source = fileread(file);
    source = regexprep(source, '(?m)^    addrBits = [^;]*;', sprintf('    addrBits = %d;', addrBits));
    source = regexprep(source, '(?m)^    fracBits = [^;]*;', sprintf('    fracBits = %d;', fracBits));
    source = regexprep(source, '(?m)^    outputMode = [^;]*;', ['    outputMode = ''', outputMode, ''';']);
    fid = fopen(file, 'w', 'n', 'UTF-8'); assert(fid >= 0);
    fprintf(fid, '%s', source); fclose(fid);
    oldPath = path;
    restore = onCleanup(@() restorePath(oldPath));
    addpath(toolsDir, fullfile(folder, 'float'), '-begin');
    clear generateReciprocalLUT exportMeteringLUT
    assert(strcmpi(which('generateReciprocalLUT'), file));
    info = generateReciprocalLUT();
end

function restorePath(oldPath)
    clear generateReciprocalLUT exportMeteringLUT meteringFileSHA256
    path(oldPath);
end

function removeOwned(folder, parent)
    file = java.io.File(folder); root = java.io.File(parent);
    absolute = char(file.getCanonicalPath()); base = char(root.getCanonicalPath());
    assert(startsWith(absolute, [base, filesep], 'IgnoreCase', true) && ...
        ~strcmpi(absolute, base), 'reciprocalLUTTestFixture:UnsafeCleanup', ...
        '仅清理当前测试创建的临时目录。');
    if isfolder(absolute), rmdir(absolute, 's'); end
end
