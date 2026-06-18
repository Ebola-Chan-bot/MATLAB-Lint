function tf = isValidIdentifier(c)
if strlength(string(c)) == 0
    tf = false;
    return;
end

c = char(c);
if ~(isletter(c(1)) || c(1) == '_')
    tf = false;
    return;
end

tf = all(isstrprop(c(2:end), 'alphanum') | c(2:end) == '_');
end
