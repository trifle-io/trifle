defmodule TrifleAdmin.Pagination do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Trifle.Repo

  @default_per_page 25

  def default_per_page, do: @default_per_page

  def sanitize_query(nil), do: ""

  def sanitize_query(query) do
    query
    |> to_string()
    |> String.trim()
  end

  def parse_page(nil), do: 1
  def parse_page(""), do: 1
  def parse_page(page) when is_integer(page) and page > 0, do: page

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, _} when value > 0 -> value
      _ -> 1
    end
  end

  def parse_page(_), do: 1

  def paginate(query, page, per_page \\ @default_per_page) do
    per_page = normalize_per_page(per_page)

    count_query =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> exclude(:select)

    total_count = Repo.aggregate(count_query, :count, :id)
    pagination = build(total_count, page, per_page)

    entries =
      query
      |> limit(^per_page)
      |> offset(^((pagination.page - 1) * per_page))
      |> Repo.all()

    {entries, pagination}
  end

  def build(total_count, page, per_page) do
    total_pages = total_pages(total_count, per_page)
    page = clamp(page, 1, total_pages)
    from = if total_count == 0, do: 0, else: (page - 1) * per_page + 1
    to = min(page * per_page, total_count)

    %{
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      from: from,
      to: to,
      pages: page_window(page, total_pages),
      has_prev: page > 1,
      has_next: page < total_pages,
      prev_page: if(page > 1, do: page - 1, else: nil),
      next_page: if(page < total_pages, do: page + 1, else: nil)
    }
  end

  def list_params(query, page) do
    query = sanitize_query(query)

    []
    |> maybe_add_param(:q, query, &(&1 != ""))
    |> maybe_add_param(:page, page, &page_param?/1)
    |> Enum.reverse()
  end

  defp maybe_add_param(params, key, value, predicate) do
    if predicate.(value) do
      [{key, value} | params]
    else
      params
    end
  end

  defp page_param?(value) when is_integer(value), do: value > 1
  defp page_param?(_), do: false

  defp normalize_per_page(per_page) when is_integer(per_page) and per_page > 0, do: per_page
  defp normalize_per_page(_), do: @default_per_page

  defp total_pages(0, _per_page), do: 1
  defp total_pages(total_count, per_page), do: div(total_count + per_page - 1, per_page)

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp page_window(page, total_pages) do
    cond do
      total_pages <= 7 ->
        Enum.to_list(1..total_pages)

      page <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total_pages]

      page >= total_pages - 3 ->
        [1, :ellipsis] ++ Enum.to_list((total_pages - 4)..total_pages)

      true ->
        [1, :ellipsis, page - 1, page, page + 1, :ellipsis, total_pages]
    end
  end
end
