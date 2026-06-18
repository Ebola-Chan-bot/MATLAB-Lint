function endLine = findBlockEndLine(nd)
%FINDBLOCKENDLINE 用 righttreepos+pos2lc 推断控制块匹配的 end 行。
% 对 IF/FOR/WHILE/SWITCH/TRY/FUNCTION 的 AST 节点，返回其子树最右行号。
if count(nd) == 0
	endLine = 0;
	return;
end
[endLine, ~] = pos2lc(nd, righttreepos(nd));
end
