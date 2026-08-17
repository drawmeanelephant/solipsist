# Cooklang Stunt (Stunts/cook-one)

This stunt verifies Cooklang recipe handling in Boris (`--input-format cooklang` or `.cook` files in content trees).

Boris parses Cooklang ingredients (`@sugar{2%tbsp}`), cookware (`#skillet`), and timers (`~{10%minutes}`) into typed nodes in `graph.json`.
