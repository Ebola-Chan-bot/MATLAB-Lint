function issues = mlint_noNonarithCast(filePath)
%mlint_noNonarithCast 禁止在无算术运算场景下使用整数类型转换。

if nargin == 0
    issues = "禁止无算术运算场景下使用整数类型转换";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    cs = char(MatlabLint.stripStringLiterals(s));

    hasCast = false;
    for fn = ["uint64", "uint32", "int64", "int32"]
        if contains(cs, fn + "(" | fn + " (")
            hasCast = true;
            break;
        end
    end
    if ~hasCast
        continue;
    end

    hasArith = false;
    for op = ["+", "-", "*", "/", "^", ".*", "./", ".^"]
        if contains(cs, op)
            hasArith = true;
            break;
        end
    end
    if hasArith
        continue;
    end

    issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_noNonarithCast", ...
        sprintf('存在无算术运算的整数类型转换："%s"，建议保留原类型或仅在算术前转换', s))); %#ok<AGROW>
end

issues = table(issuesBuilder);
end



