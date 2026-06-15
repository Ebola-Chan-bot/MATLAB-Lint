function fnName = extractFunctionName(decl)
fnName = "";
s = strtrim(string(decl));
if ~startsWith(s, "function ")
    return;
end

s = strtrim(extractAfter(s, "function "));
if contains(s, "=")
    s = strtrim(extractAfter(s, "="));
end
if contains(s, "(")
    s = strtrim(extractBefore(s, "("));
end
if isValidIdentifier(s)
    fnName = s;
end
end
