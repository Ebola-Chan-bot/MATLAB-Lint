function ids = collectRhsIds(node)
%COLLECTRHSIDS 递归遍历子树，提取所有 ID 字符串。
if count(node) == 0
    ids = strings(0, 1);
    return;
end
ids = iCollectRecursive(node, strings(0, 1));
end

function ids = iCollectRecursive(nxt, ids)
if count(nxt) == 0
    return;
end

if char(nxt.kind) == "ID"
    ids(end + 1) = string(nxt.string); %#ok<AGROW>
    return;
end

if count(Left(nxt)) > 0
    ids = iCollectRecursive(Left(nxt), ids);
end
if count(Right(nxt)) > 0
    ids = iCollectRecursive(Right(nxt), ids);
end
if count(Arg(nxt)) > 0
    ids = iCollectRecursive(Arg(nxt), ids);
end
try
    nxt = Next(nxt);
    if count(nxt) > 0
        ids = iCollectRecursive(nxt, ids);
    end
catch
end
end
