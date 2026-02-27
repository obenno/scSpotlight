export function buildHoverText({
  mode,
  panelIndex,
  pointIndex,
  groupByValues = [],
  splitByValues = [],
  expressionValues = [],
  splitArrByMeta,
  formatExpr,
}) {
  const fmt = typeof formatExpr === "function" ? formatExpr : (v) => String(v);
  const splitFn =
    typeof splitArrByMeta === "function"
      ? splitArrByMeta
      : (arr, by) => {
          const out = {};
          for (let i = 0; i < by.length; i++) {
            const key = by[i];
            if (!out[key]) out[key] = [];
            out[key].push(arr[i]);
          }
          return out;
        };

  switch (mode) {
    case "clusterOnly":
      return `Cat: ${groupByValues[pointIndex]}`;

    case "cluster+expr+noSplit":
      if (panelIndex === 0) {
        return `Cat: ${groupByValues[pointIndex]}`;
      }
      return `Expr: ${fmt(expressionValues[pointIndex])}`;

    case "cluster+expr+twoSplit": {
      const splitCategory = splitFn(groupByValues, splitByValues);
      const splitExpr = splitFn(expressionValues, splitByValues);
      const keys = Object.keys(splitCategory);
      const splitIdx = Math.floor(panelIndex / 2);
      const key = keys[splitIdx];
      if (!key) return null;
      if (panelIndex % 2 === 0) {
        return `Cat: ${splitCategory[key][pointIndex]}`;
      }
      return `Expr: ${fmt(splitExpr[key][pointIndex])}`;
    }

    case "cluster+multiSplit": {
      const splitCategory = splitFn(groupByValues, splitByValues);
      const keys = Object.keys(splitCategory);
      const key = keys[panelIndex];
      if (!key) return null;
      return `Cat: ${splitCategory[key][pointIndex]}`;
    }

    case "cluster+expr+multiSplit": {
      const splitExpr = splitFn(expressionValues, splitByValues);
      const keys = Object.keys(splitExpr);
      const key = keys[panelIndex];
      if (!key) return null;
      return `Expr: ${fmt(splitExpr[key][pointIndex])}`;
    }

    default:
      return null;
  }
}
