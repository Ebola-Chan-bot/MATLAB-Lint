function result = singleUseVariable_False_IfCondRead(inputValue)
% L2: 赋值 — 非自引用，避免 isSelfRef 豁免
valueType = lower(inputValue);
% L4: if 条件中读取 valueType — CFG 应能到达但 readNodeIds 漏掉 IF 内的读
if strlength(valueType) > 1
    % L6: 另一个赋值，成为 blocker
    valueType = extractBetween(valueType, 2, strlength(valueType)-1);
end
result = valueType;
end
