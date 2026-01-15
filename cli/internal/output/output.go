package output

import (
  "encoding/csv"
  "encoding/json"
  "fmt"
  "io"
  "os"
  "strings"
)

type Table struct {
  Columns []string
  Rows    [][]string
}

func PrintJSON(w io.Writer, value any) error {
  encoded, err := json.MarshalIndent(value, "", "  ")
  if err != nil {
    return err
  }

  _, err = w.Write(append(encoded, '\n'))
  return err
}

func PrintTable(w io.Writer, table Table) {
  if len(table.Columns) == 0 {
    return
  }

  widths := make([]int, len(table.Columns))
  for i, col := range table.Columns {
    widths[i] = len(col)
  }

  for _, row := range table.Rows {
    for i, cell := range row {
      if i >= len(widths) {
        break
      }
      if len(cell) > widths[i] {
        widths[i] = len(cell)
      }
    }
  }

  writeRow := func(values []string) {
    for i, value := range values {
      if i > 0 {
        fmt.Fprint(w, "  ")
      }
      fmt.Fprint(w, padRight(value, widths[i]))
    }
    fmt.Fprint(w, "\n")
  }

  writeRow(table.Columns)
  separators := make([]string, len(table.Columns))
  for i, width := range widths {
    separators[i] = strings.Repeat("-", width)
  }
  writeRow(separators)

  for _, row := range table.Rows {
    normalized := make([]string, len(table.Columns))
    copy(normalized, row)
    writeRow(normalized)
  }
}

func PrintCSV(w io.Writer, table Table) error {
  writer := csv.NewWriter(w)
  if err := writer.Write(table.Columns); err != nil {
    return err
  }

  for _, row := range table.Rows {
    if err := writer.Write(row); err != nil {
      return err
    }
  }

  writer.Flush()
  return writer.Error()
}

func ExtractTable(payload map[string]any) (Table, bool) {
  raw, ok := payload["table"]
  if !ok || raw == nil {
    return Table{}, false
  }

  rawMap, ok := raw.(map[string]any)
  if !ok {
    return Table{}, false
  }

  columnsValue, ok := rawMap["columns"]
  if !ok {
    return Table{}, false
  }

  columns := toStringSlice(columnsValue)
  if len(columns) == 0 {
    return Table{}, false
  }

  rowsValue, ok := rawMap["rows"]
  if !ok {
    return Table{}, false
  }

  rows := toStringMatrix(rowsValue, len(columns))
  return Table{Columns: columns, Rows: rows}, true
}

func PrintTableOrJSON(payload map[string]any, format string) error {
  if format == "table" || format == "csv" {
    if table, ok := ExtractTable(payload); ok {
      switch format {
      case "table":
        PrintTable(os.Stdout, table)
        return nil
      case "csv":
        return PrintCSV(os.Stdout, table)
      }
    }
  }

  return PrintJSON(os.Stdout, payload)
}

func toStringSlice(value any) []string {
  list, ok := value.([]any)
  if !ok {
    return nil
  }

  out := make([]string, 0, len(list))
  for _, item := range list {
    out = append(out, fmt.Sprint(item))
  }
  return out
}

func toStringMatrix(value any, columns int) [][]string {
  rowsRaw, ok := value.([]any)
  if !ok {
    return nil
  }

  rows := make([][]string, 0, len(rowsRaw))
  for _, rawRow := range rowsRaw {
    list, ok := rawRow.([]any)
    if !ok {
      continue
    }
    row := make([]string, 0, columns)
    for _, cell := range list {
      row = append(row, fmt.Sprint(cell))
    }
    if len(row) < columns {
      for len(row) < columns {
        row = append(row, "")
      }
    }
    rows = append(rows, row)
  }

  return rows
}

func padRight(value string, width int) string {
  if len(value) >= width {
    return value
  }
  return value + strings.Repeat(" ", width-len(value))
}
