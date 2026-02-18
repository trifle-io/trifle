defmodule Trifle.Mailer.Template do
  @moduledoc """
  Shared renderer for transactional emails.
  """

  @default_brand "Trifle"

  @type option ::
          {:brand, String.t()}
          | {:headline, String.t()}
          | {:greeting, String.t()}
          | {:intro_lines, [String.t()]}
          | {:action_label, String.t()}
          | {:action_url, String.t()}
          | {:outro_lines, [String.t()]}
          | {:footer_lines, [String.t()]}

  @spec action_email([option()]) :: %{html: String.t(), text: String.t()}
  def action_email(opts) when is_list(opts) do
    brand = Keyword.get(opts, :brand, @default_brand)
    headline = opts |> Keyword.fetch!(:headline) |> normalize_line()
    greeting = opts |> Keyword.get(:greeting, "Hi,") |> normalize_line()
    intro_lines = opts |> Keyword.get(:intro_lines, []) |> normalize_lines()
    action_label = opts |> Keyword.get(:action_label, nil) |> normalize_optional_line()
    action_url = opts |> Keyword.get(:action_url, nil) |> normalize_optional_line()
    outro_lines = opts |> Keyword.get(:outro_lines, []) |> normalize_lines()
    footer_lines = opts |> Keyword.get(:footer_lines, []) |> normalize_lines()

    %{
      html:
        render_html(
          brand,
          headline,
          greeting,
          intro_lines,
          action_label,
          action_url,
          outro_lines,
          footer_lines
        ),
      text:
        render_text(
          headline,
          greeting,
          intro_lines,
          action_label,
          action_url,
          outro_lines,
          footer_lines
        )
    }
  end

  defp render_text(
         headline,
         greeting,
         intro_lines,
         action_label,
         action_url,
         outro_lines,
         footer_lines
       ) do
    sections =
      [
        [headline],
        [greeting],
        intro_lines,
        action_section(action_label, action_url),
        outro_lines,
        footer_lines
      ]
      |> Enum.reject(&Enum.empty?/1)

    """
    ==============================

    #{Enum.map_join(sections, "\n\n", &Enum.join(&1, "\n"))}

    ==============================
    """
    |> String.trim_trailing()
  end

  defp action_section(nil, nil), do: []
  defp action_section(label, nil), do: [label]
  defp action_section(nil, url), do: [url]
  defp action_section(label, url), do: [label <> ":", url]

  @font_stack "'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

  defp render_html(
         brand,
         headline,
         greeting,
         intro_lines,
         action_label,
         action_url,
         outro_lines,
         footer_lines
       ) do
    """
    <div style="margin:0;padding:40px 16px;background-color:#f8fafc;font-family:#{@font_stack};color:#0f172a;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 auto;max-width:560px;">
        <tr>
          <td style="padding:0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:16px;overflow:hidden;">
              <tr>
                <td style="height:4px;background:linear-gradient(90deg,#0d9488,#14b8a6,#06b6d4);font-size:0;line-height:0;">&nbsp;</td>
              </tr>
              <tr>
                <td style="padding:36px 32px 32px 32px;">
                  <p style="margin:0 0 20px 0;font-size:22px;line-height:1.35;font-weight:700;color:#0f172a;">#{escape_html(headline)}</p>
                  #{paragraph_html(greeting)}
                  #{paragraphs_html(intro_lines)}
                  #{action_html(action_label, action_url)}
                  #{paragraphs_html(outro_lines)}
                  #{divider_html(footer_lines)}
                  #{paragraphs_html(footer_lines, "#64748b", "13px", "1.5")}
                </td>
              </tr>
            </table>
            <p style="margin:20px 0 0 0;text-align:center;font-size:11px;line-height:1.4;color:#94a3b8;letter-spacing:0.04em;">#{escape_html(brand)}</p>
          </td>
        </tr>
      </table>
    </div>
    """
  end

  defp paragraphs_html(lines, color \\ "#334155", size \\ "15px", line_height \\ "1.7") do
    Enum.map_join(lines, "", &paragraph_html(&1, color, size, line_height))
  end

  defp paragraph_html(line, color \\ "#334155", size \\ "15px", line_height \\ "1.7") do
    ~s(<p style="margin:0 0 14px 0;font-size:#{size};line-height:#{line_height};color:#{color};">#{escape_html(line)}</p>)
  end

  defp action_html(_label, nil), do: ""

  defp action_html(label, url) do
    button_label = if is_binary(label) and label != "", do: label, else: "Open link"
    escaped_url = escape_html(url)

    """
    <p style="margin:24px 0 20px 0;">
      <a href="#{escaped_url}" style="display:inline-block;background-color:#14b8a6;color:#ffffff;text-decoration:none;font-size:14px;line-height:1;font-weight:600;padding:14px 28px;border-radius:100px;letter-spacing:0.01em;">
        #{escape_html(button_label)}
      </a>
    </p>
    <p style="margin:0 0 14px 0;font-size:12px;line-height:1.5;color:#94a3b8;">
      If the button doesn't work, copy and paste this link into your browser:<br />
      <a href="#{escaped_url}" style="color:#14b8a6;text-decoration:underline;">#{escaped_url}</a>
    </p>
    """
  end

  defp divider_html([]), do: ""

  defp divider_html(_lines) do
    ~s(<hr style="border:none;border-top:1px solid #f1f5f9;margin:24px 0 18px 0;" />)
  end

  defp normalize_lines(lines) when is_list(lines) do
    lines
    |> Enum.map(&normalize_line/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_lines(_), do: []

  defp normalize_optional_line(nil), do: nil
  defp normalize_optional_line(value), do: normalize_line(value)

  defp normalize_line(value) when is_binary(value), do: String.trim(value)
  defp normalize_line(value), do: to_string(value) |> String.trim()

  defp escape_html(value), do: Plug.HTML.html_escape(value)
end
