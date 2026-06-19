function ids = collectRhsIds(node)
%COLLECTRHSIDS 递归遍历子树，提取所有 ID 字符串。
if count(node) == 0
    ids = strings(0, 1);
    return;
end
acc = MATLAB.Containers.Vector();
iCollectRecursive(node, acc);
ids = string(acc.Data(:));
end

function iCollectRecursive(nxt, acc)
if count(nxt) == 0
    return;
end

if char(nxt.kind) == "ID"
    acc.PushBack(string(nxt.string));
    return;
end

if count(Left(nxt)) > 0
    iCollectRecursive(Left(nxt), acc);
end
if count(Right(nxt)) > 0
    iCollectRecursive(Right(nxt), acc);
end
if count(Arg(nxt)) > 0
    iCollectRecursive(Arg(nxt), acc);
end
try
    nxt = Next(nxt);
    if count(nxt) > 0
        iCollectRecursive(nxt, acc);
    end
catch
end
end
