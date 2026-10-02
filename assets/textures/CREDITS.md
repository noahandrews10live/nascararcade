# Surface textures

All CC0 (public domain). Each is reduced to a 1024 px neutral grey detail map
(luminance only, normalised; the track's own colours tint it in the game) plus
its OpenGL-convention normal map.

| File | Source | Author | Real size |
|---|---|---|---|
| `asphalt_*` | [Poly Haven: Asphalt Track](https://polyhaven.com/a/asphalt_track) | Dimitrios Savva | 2 m (tiled at 3 m) |
| `concrete_*` | [Poly Haven: Concrete](https://polyhaven.com/a/concrete) | Rob Tuytel | 4 m |
| `grass_*` | [ambientCG: Grass 001](https://ambientcg.com/view?id=Grass001) | ambientCG | 1.4 m (tiled at 2.8 m) |

`asphalt_rough.jpg` and `concrete_rough.jpg` are 512 px roughness maps made from
the albedo maps above by `tools/make_roughness.py` (same licence).
