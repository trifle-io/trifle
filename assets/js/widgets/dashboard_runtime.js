import { registerDashboardGridHook } from "./dashboard_runtime/dashboard_grid_hook";
import { registerDashboardAnnotationsDataHook } from "./dashboard_runtime/dashboard_annotations_data_hook";
import { registerDashboardWidgetDataHook } from "./dashboard_runtime/dashboard_widget_data_hook";
import { registerExpandedWidgetViewHook } from "./dashboard_runtime/expanded_widget_view_hook";
import { registerExpandedAgGridTableHook } from "./dashboard_runtime/expanded_aggrid_table_hook";

export const registerDashboardRuntimeHooks = (Hooks, deps) => {
  registerDashboardGridHook(Hooks, deps);
  registerDashboardAnnotationsDataHook(Hooks, deps);
  registerDashboardWidgetDataHook(Hooks, deps);
  registerExpandedWidgetViewHook(Hooks, deps);
  registerExpandedAgGridTableHook(Hooks, deps);
};
