defmodule Cldr.Rbnf.Gen do
  @moduledoc """
  Generates test data values for RBNF.

  Only to be used if something changes in
  CLDR

  The json included here has the standard test
  keys used by RBNF testing. The values will be
  replaced with generated data.

  """
  @json ~S"""
  {
    "-1141": "−1 141.",
    "-1142": "−1 142.",
    "-1143": "−1 143.",
    "-100": "−100.",
    "-75": "−75-и",
    "-50": "−50.",
    "-24": "−24.",
    "0": "0.",
    "1": "1-ви",
    "2": "2-и",
    "3": "3-и",
    "4": "4-ти",
    "5": "5-и",
    "6": "6-и",
    "7": "7-и",
    "8": "8-и",
    "9": "9-и",
    "10": "10-и",
    "11": "11-и",
    "12": "12-и",
    "13": "13-и",
    "14": "14-и",
    "15": "15-и",
    "16": "16-и",
    "17": "17-и",
    "18": "18-и",
    "19": "19-и",
    "20": "20-и",
    "21": "21-и",
    "22": "22-и",
    "23": "23-и",
    "24": "24-ти",
    "25": "25-и",
    "26": "26-и",
    "27": "27-и",
    "28": "28-и",
    "29": "29-и",
    "30": "30-и",
    "31": "31-и",
    "32": "32-и",
    "33": "33-и",
    "34": "34-и",
    "35": "35-и",
    "36": "36-и",
    "37": "37-и",
    "38": "38-и",
    "39": "39-и",
    "40": "40-и",
    "41": "41-и",
    "42": "42-ри",
    "43": "43-и",
    "44": "44-и",
    "45": "45-и",
    "46": "46-и",
    "47": "47-и",
    "48": "48-и",
    "49": "49-и",
    "50": "50-и",
    "51": "51-ви",
    "52": "52-и",
    "53": "53-и",
    "54": "54-и",
    "55": "55-и",
    "56": "56-и",
    "57": "57-и",
    "58": "58-и",
    "59": "59-и",
    "60": "60-и",
    "61": "61-и",
    "62": "62-и",
    "63": "63-и",
    "64": "64-и",
    "65": "65-и",
    "66": "66-и",
    "67": "67-и",
    "68": "68-и",
    "69": "69-и",
    "70": "70-и",
    "71": "71-и",
    "72": "72-и",
    "73": "73-и",
    "74": "74-и",
    "75": "75-и",
    "76": "76-и",
    "77": "77-и",
    "78": "78-и",
    "79": "79-и",
    "80": "80-и",
    "81": "81-и",
    "82": "82-и",
    "83": "83-и",
    "84": "84-и",
    "85": "85-и",
    "86": "86-и",
    "87": "87-и",
    "88": "88-и",
    "89": "89-и",
    "90": "90-и",
    "91": "91-и",
    "92": "92-и",
    "93": "93-и",
    "94": "94-и",
    "95": "95-и",
    "96": "96-и",
    "97": "97-и",
    "98": "98-и",
    "99": "99-и",
    "100": "100.",
    "321": "321.",
    "322": "322.",
    "323": "323.",
    "1141": "1141-и",
    "1142": "1142-и",
    "1143": "1143-и",
    "10311": "10 311.",
    "138400": "138 400-тен"
  }
  """

  def gen(rule, locale) do
    @json
    |> Jason.decode!()
    |> Enum.map(fn {k, _v} ->
      i = String.to_integer(k)
      {:ok, v} = Cldr.Number.to_string(i, format: rule, locale: locale)
      {i, v}
    end)
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> "\"#{k}\": \"#{v}\"" end)
    |> Enum.join(",\n")
    |> IO.puts()

    nil
  end
end
