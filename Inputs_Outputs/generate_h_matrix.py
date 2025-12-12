import numpy as np
from circuit_gen import gen, gen_d18, get_params

# Choose code parameters
d = 12              # code distance (change if needed)
p = 0.001           # error probability (used for priors)
basis = 'Z'         # or 'X'

# Generate the circuit and extract H
if d == 18:
    circuit = gen_d18(p=p, basis=basis)
else:
    circuit = gen(p=p, basis=basis)

chk, obs, priors = get_params(circuit)  # chk is the H matrix

# Save to file
np.savetxt("H_matrix.txt", chk, fmt="%d")
print("H matrix saved to H_matrix.txt")
