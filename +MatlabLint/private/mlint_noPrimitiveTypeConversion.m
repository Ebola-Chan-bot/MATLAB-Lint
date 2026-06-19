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
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
        continue;
    end

    fn = lower(strtrim(string(lhs.string)));
    if ~any(castFns == fn)
        continue;
    end

    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, double(nd.lineno), "mlint_noPrimitiveTypeConversion", ...
        sprintf('通常没有必要做 %s(...) 基础类型转换，建议省去；如确有旧接口兼容要求可保留', fn)}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end