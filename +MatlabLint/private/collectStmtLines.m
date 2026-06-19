function stmtLines = collectStmtLines(FullTree, fStart, fEnd, extraLines, extraKinds)
%COLLECTSTMTLINES 收集函数内所有语句节点索引；保留旧函数名以兼容调用方。
% extraLines: 额外的节点索引数组（如函数结束节点）
% extraKinds: 额外的控制块类型（如 "FUNCTION"）

if nargin < 4
    extraLines = [];
end
if nargin < 5
    extraKinds = strings(0, 1);
end

stmtLines = double(extraLines(:)');

% 赋值行
ix = FullTree.mtfind('Kind', 'EQUALS').indices;
if ~isempty(ix)
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fStart && righttreepos(nd) <= fEnd
            stmtLines(end + 1) = double(nd.indices); %#ok<AGROW>
        end
    end
end

% 引用行
ix = FullTree.mtfind('Kind', 'ID').indices;
if ~isempty(ix)
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fStart && righttreepos(nd) <= fEnd
            stmtLines(end + 1) = double(nd.indices); %#ok<AGROW>
        end
    end
end

% 控制块头尾
ctrl = ["IF","ELSEIF","ELSE","FOR","PARFOR","WHILE","SWITCH","CASE","OTHERWISE", ...
        "TRY","CATCH","RETURN","BREAK","CONTINUE","FUNCTION"];
if ~isempty(extraKinds)
    ctrl = [ctrl, extraKinds];
end
for ki = 1:numel(ctrl)
    nodes = FullTree.mtfind('Kind', ctrl(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fStart && righttreepos(nd) <= fEnd
            stmtLines(end + 1) = double(nd.indices); %#ok<AGROW>
        end
    end
end

% mtree 不产出 END 节点，从控制块头推断 end 节点位置
blockKinds = ["IF","SWITCH","FOR","PARFOR","WHILE","TRY","FUNCTION"];
for ki = 1:numel(blockKinds)
    nodes = FullTree.mtfind('Kind', blockKinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fStart && righttreepos(nd) <= fEnd
            stmtLines(end + 1) = double(nd.indices); %#ok<AGROW>
        end
    end
end

stmtLines = unique(stmtLines);
stmtLines = stmtLines(stmtLines >= 0);
end
