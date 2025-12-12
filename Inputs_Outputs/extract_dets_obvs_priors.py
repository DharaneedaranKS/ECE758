import pickle
import numpy as np

# Load your .pkl file
with open("unconverged_Z_0.001.pkl", "rb") as f:
    dets, observables, priors, mean_error, errors = pickle.load(f)

# Convert boolean to 0/1 integers
dets_bin = np.array(dets, dtype=int)
obs_bin = np.array(observables, dtype=int)
priors_arr = np.array(priors)

# Save as plain text
np.savetxt("dets_0_1.txt", dets_bin, fmt="%d")
np.savetxt("observables_0_1.txt", obs_bin, fmt="%d")
np.savetxt("priors.txt", priors_arr, fmt="%.6f")
