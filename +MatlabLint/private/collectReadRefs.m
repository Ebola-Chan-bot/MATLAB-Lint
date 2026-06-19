function refMap = collectReadRefs(FullTree)
%COLLECTREADREFS 收集全文变量读引用 — key: varName, value: dictionary(nodeIdx→count)。
% 排除等号左侧的写入 ID。

refMap = configureDictionary('string', 'dictionary');
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

    nodeIdx = double(nd.indices);
    if ~isKey(refMap, name)
        refMap(name) = configureDictionary('double', 'double');
    end
    nodeMap = refMap(name);
    if isKey(nodeMap, nodeIdx)
        nodeMap(nodeIdx) = nodeMap(nodeIdx) + 1;
    else
        nodeMap(nodeIdx) = 1;
    end
    refMap(name) = nodeMap;
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
