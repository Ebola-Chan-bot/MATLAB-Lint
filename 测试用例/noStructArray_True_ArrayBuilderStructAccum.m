function result = noStructArray_True_ArrayBuilderStructAccum()
% 复现：用 ArrayBuilder.Append(struct(...)) 积累 struct 的模式
% 应被 mlint_noStructArray 报告

builder = MATLAB.DataTypes.ArrayBuilder();
for i = 1:10
    builder.Append(struct('name', i, 'val', i * 2));
end
result = builder.Harvest();
end
