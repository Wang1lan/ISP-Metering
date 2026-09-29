function hash = meteringFileSHA256(filePath)
%METERINGFILESHA256 对文件原始字节计算 SHA-256，仅在离线/初始化时使用。
    assert(usejava('jvm'), 'meteringFileSHA256:JVMRequired', ...
        'SHA-256 校验需要 MATLAB JVM；请启用 JVM，不能跳过完整性校验。');
    [fid, message] = fopen(filePath, 'rb');
    assert(fid >= 0, 'meteringFileSHA256:ReadFailed', ...
        '无法读取文件 %s：%s', filePath, message);
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
    [message, number] = ferror(fid);
    % R2022a 的正常 EOF 对应 ferror=-4；其它读取错误仍拒绝。
    assert(number == 0 || (number == -4 && feof(fid)), ...
        'meteringFileSHA256:ReadFailed', '%s', message);
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(typecast(bytes, 'int8'));
        hash = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
    catch cause
        error('meteringFileSHA256:DigestFailed', ...
            'SHA-256 计算失败，不能跳过校验：%s', cause.message);
    end
end
