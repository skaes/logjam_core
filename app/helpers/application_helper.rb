# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def time_number(f)
    number_with_precision(f.to_f, :delimiter => ",", :separator => ".", :precision => 2)
  end
  def memory_number(f)
    number_with_precision(f.floor, :delimiter => ",", :separator => ".", :precision => 0)
  end
end
