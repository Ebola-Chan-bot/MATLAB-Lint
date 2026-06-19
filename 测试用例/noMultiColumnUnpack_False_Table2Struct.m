function result = noMultiColumnUnpack_False_Table2Struct()
t = table([1;2], ['a';'b'], 'VariableNames', ["x","y"]);
result = table2struct(t);
end
