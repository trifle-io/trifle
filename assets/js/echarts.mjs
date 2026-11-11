// ECharts, limited to what the app draws.
//
// `import * as echarts from "echarts"` pulls in every chart type and component
// (maps, graphs, trees, 3D-style series, toolbox, data zoom, ...), most of which
// this app never uses. This module registers only the pieces listed below and
// re-exports the same API, so the rest can be left out of the bundle.
//
// Adding a chart? A series type or component that is not registered here does
// not fail loudly: the chart simply does not draw it. Register it below, and run
// `node --test assets/test/echarts_registration_test.mjs`, which compares this build
// against the full library for every option shape the app uses.
import * as echarts from "echarts/core";
import { BarChart, HeatmapChart, LineChart, PieChart, ScatterChart } from "echarts/charts";
import {
  AriaComponent,
  AxisPointerComponent,
  CalendarComponent,
  DatasetComponent,
  GraphicComponent,
  GridComponent,
  LegendComponent,
  MarkAreaComponent,
  MarkLineComponent,
  MarkPointComponent,
  TitleComponent,
  TooltipComponent,
  TransformComponent,
  VisualMapComponent,
} from "echarts/components";
import { LabelLayout, LegacyGridContainLabel, UniversalTransition } from "echarts/features";
import { CanvasRenderer, SVGRenderer } from "echarts/renderers";

// Registered in the same order as the full build (node_modules/echarts/index.js).
// The order decides how overlapping pieces are layered (for example a mark line
// against a mark point), so keeping it identical keeps charts pixel-identical.
echarts.use([
  // Charts render as SVG (see utils/charts.js); canvas is kept available.
  CanvasRenderer,
  SVGRenderer,
  // Series types: timeseries (line, bar, area), category (bar, pie),
  // distribution (bar, scatter, heatmap), KPI sparklines (line).
  LineChart,
  BarChart,
  PieChart,
  ScatterChart,
  HeatmapChart,
  // Components referenced by chart options.
  GridComponent, // xAxis / yAxis / grid, including time and category axes
  CalendarComponent,
  GraphicComponent, // "no data" text overlays
  TooltipComponent,
  AxisPointerComponent,
  TitleComponent,
  MarkPointComponent,
  MarkLineComponent,
  MarkAreaComponent,
  LegendComponent, // plain and `type: "scroll"`
  VisualMapComponent, // heatmap colour scale
  AriaComponent,
  TransformComponent,
  DatasetComponent,
  // Morphing between option updates and label overlap handling.
  UniversalTransition,
  LabelLayout,
  // `grid.containLabel`, used by most cartesian charts here, is a separate
  // feature since ECharts 6. Without it axis labels are clipped.
  LegacyGridContainLabel,
]);

export * from "echarts/core";
