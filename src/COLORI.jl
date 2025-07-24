using Plots

values = [1, 1, 1, 1, 1]
labels = ["A", "B", "C", "D", "E"]
pie_colors = [:gray90 :slategray1 :lightgoldenrod1 :tomato2 :palegreen2]
p = pie(values; color=pie_colors)
display(p)