function refMap = collectReadRefs(FullTree)
%COLLECTREADREFS 收集全文变量读引用 — key: varName, value: dictionary(line→count)。
% 排除等号左侧的写入 ID。

refMap = dictionary;
ix = FullTree.mtfind('Kind', 'ID').indices;
if isempty(ix)
    return;
end

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    name = char(nd.string);
    if isempty(name) || iIsWriteId(ix(i), nd)
        continue;
    end

    ln = double(nd.lineno);
    if ~isKey(refMap, name)
        refMap(name) = dictionary;
    end
    lineMap = refMap(name);
    if isKey(lineMap, ln)
        lineMap(ln) = lineMap(ln) + 1;
    else
        lineMap(ln) = 1;
    end
    refMap(name) = lineMap;
end
end

% -------------------------------------------------------------------------
function tf = iIsWriteId(nodeIx, p)
tf = false;
p = Parent(p);
if count(p) == 0 || ~strcmp(char(p.kind), 'EQUALS')
    return;
end
try
    tf = any(Left(p).indices == nodeIx);
catch
    tf = false;
end
end
