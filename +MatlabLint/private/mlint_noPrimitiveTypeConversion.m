function issues = mlint_noPrimitiveTypeConversion(filePath)
%mlint_noPrimitiveTypeConversion 建议省去通常不必要的基础类型转换。

if nargin == 0
    issues = "通常没有必要做基础数据类型转换，建议省去";
    return;
end

tree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

calls = tree.mtfind('Kind', 'CALL');
if count(calls) == 0
    issues = table(issuesBuilder);
    return;
end

castFns = ["char","string","double","single", ...
    "int8","int16","int32","int64", ...
    "uint8","uint16","uint32","uint64","logical"];

cix = calls.indices;
for i = 1:numel(cix)
    nd = tree.select(cix(i));
    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(lhs.kind, 'ID')
        continue;
    end

    fn = lower(strtrim(lhs.string));
    if ~any(castFns == fn)
        continue;
    end

    if fn == "string"
        msg = "通常没有必要做 ... 基础类型转换，建议省去；请优先检查是否误用了 cell 索引（应使用 {} 取内容而非 () 取 cell），先修正索引方式再评估是否仍需转换";
    else
        msg = sprintf('通常没有必要做 %s(...) 基础类型转换，建议省去；必需转换的建议注释理由', fn);
    end

    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, nd.lineno, "mlint_noPrimitiveTypeConversion", ...
        msg}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end
