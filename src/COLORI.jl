using Plots

values = [1, 1, 1, 1]
labels = ["A", "B", "C", "D"]
pie_colors = [:purple, :blue, :lawngreen, :yellow]
p = pie(values; color=pie_colors)
display(p)