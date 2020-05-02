import Domo

deftag App.Core.Order.Quantity do
  for_type __MODULE__.Units.t() | __MODULE__.Kilograms.t()

  deftag Units do
    for_type __MODULE__.Packages.t() | __MODULE__.Boxes.t()

    deftag Packages, for_type: integer
    deftag Boxes, for_type: integer
  end

  deftag Kilograms, for_type: float
end
