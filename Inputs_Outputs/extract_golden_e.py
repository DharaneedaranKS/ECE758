import pickle
import numpy as np
from ldpc.bposd_decoder import BpOsdDecoder
from circuit_gen import gen, get_params, gen_d18
import os

# === CONFIGURATION ===
INPUT_FILE = 'unconverged_Z_0.001.pkl'   # Your input pickle file
OUTPUT_FILE = 'golden_e_all.txt'        # Output file with one e_hat_osd per line
NUM_VECTORS = None                      # Set to None to process all

# === LOAD DATA ===
with open(INPUT_FILE, 'rb') as f:
    data = pickle.load(f)

if len(data) == 5:
    dets, observables, priors, mean_error, errors = data
else:
    dets, observables = data

# === PARSE CIRCUIT PARAMETERS ===
parts = INPUT_FILE.split('_')
basis = parts[1]
p = float(parts[2].replace('.pkl', ''))
d = int(parts[3].replace('.pkl', '').replace('d', '')) if len(parts) == 4 else 12

circuit = gen(p=p, basis=basis) if d != 18 else gen_d18(p=p, basis=basis)
chk, obs, priors = get_params(circuit)

# === DECODE ALL ===
count = len(dets) if NUM_VECTORS is None else min(NUM_VECTORS, len(dets))
with open(OUTPUT_FILE, 'w') as fout:
    for idx in range(count):
        det = dets[idx]
        decoder = BpOsdDecoder(
            chk,
            error_channel=list(priors),
            max_iter=100,
            input_vector_type='syndrome',
            osd_method='OSD_0',
            osd_order=0
        )
        e_osd = decoder.decode(det)
        fout.write(''.join(str(int(b)) for b in e_osd) + '\n')

print(f"? Extracted {count} golden outputs to '{OUTPUT_FILE}'")
