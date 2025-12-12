import numpy as np
import sys

# Configuration
ORIGINAL_FILES = {
    "H": "H_matrix.txt",
    "Priors": "priors.txt",
    "Syndromes": "dets_0_1.txt",
    "Golden": "golden_e_all.txt"
}

FORMATTED_FILES = {
    "H": "formatted_tests/H_matrix_formatted.txt",
    "Indices": "formatted_tests/sorted_indices.txt",
    "Syndromes": "formatted_tests/syndromes_formatted.txt",
    "Golden": "formatted_tests/golden_formatted.txt"
}

def verify_h_matrix():
    print("Verifying H Matrix...")
    
    # 1. Load Original (Space separated, Row-by-Row)
    # Shape: [936, 8784]
    try:
        print("  Loading Original...")
        orig = np.loadtxt(ORIGINAL_FILES["H"], dtype=int)
    except Exception as e:
        print(f"  FAILED to load original: {e}")
        return

    # 2. Load Formatted (Dense strings, Column-by-Column)
    # We expect 8784 lines, each 936 chars long.
    print("  Loading Formatted & Reconstructing...")
    reconstructed_list = []
    try:
        with open(FORMATTED_FILES["H"], 'r') as f:
            for line in f:
                bits = [int(c) for c in line.strip()]
                reconstructed_list.append(bits)
    except Exception as e:
        print(f"  FAILED to load formatted: {e}")
        return

    # This list is currently [Col0, Col1, ...]. 
    # This is a matrix of shape [8784, 936].
    # To get back to original, we must TRANSPOSE it.
    formatted_matrix = np.array(reconstructed_list) # [8784, 936]
    reconstructed_orig = formatted_matrix.T         # [936, 8784]

    # 3. Compare
    if np.array_equal(orig, reconstructed_orig):
        print("  SUCCESS: H Matrix conversion is perfect.")
    else:
        print("  FAILURE: H Matrix mismatch!")
        # Debug info
        diff = np.not_equal(orig, reconstructed_orig)
        print(f"  Differences found at: {np.argwhere(diff)}")

def verify_syndromes():
    print("\nVerifying Syndromes...")
    
    # 1. Load Original (Space separated)
    print("  Loading Original...")
    with open(ORIGINAL_FILES["Syndromes"], 'r') as f:
        orig_lines = [line.split() for line in f if line.strip()]

    # 2. Load Formatted (Dense strings, Reversed)
    print("  Loading Formatted...")
    with open(FORMATTED_FILES["Syndromes"], 'r') as f:
        fmt_lines = [list(line.strip()) for line in f if line.strip()]

    # 3. Compare
    if len(orig_lines) != len(fmt_lines):
        print(f"  FAILURE: Line count mismatch ({len(orig_lines)} vs {len(fmt_lines)})")
        return

    errors = 0
    for i in range(len(orig_lines)):
        # original is ['0', '1', '0']
        # formatted is ['0', '1', '0'] but REVERSED order
        
        # Reverse formatted back
        reconstructed = fmt_lines[i][::-1]
        
        if orig_lines[i] != reconstructed:
            errors += 1
            if errors < 5:
                print(f"  Mismatch at line {i}")
    
    if errors == 0:
        print("  SUCCESS: Syndrome conversion is perfect.")
    else:
        print(f"  FAILURE: Found {errors} mismatches.")

def verify_golden():
    print("\nVerifying Golden Vectors...")
    
    # 1. Load Original (Dense strings)
    print("  Loading Original...")
    with open(ORIGINAL_FILES["Golden"], 'r') as f:
        orig_lines = [line.strip() for line in f if line.strip()]

    # 2. Load Formatted (Dense strings, Reversed)
    print("  Loading Formatted...")
    with open(FORMATTED_FILES["Golden"], 'r') as f:
        fmt_lines = [line.strip() for line in f if line.strip()]

    # 3. Compare
    if len(orig_lines) != len(fmt_lines):
        print(f"  FAILURE: Line count mismatch")
        return

    errors = 0
    for i in range(len(orig_lines)):
        # Reverse formatted back
        reconstructed = fmt_lines[i][::-1]
        
        if orig_lines[i] != reconstructed:
            errors += 1
    
    if errors == 0:
        print("  SUCCESS: Golden Vector conversion is perfect.")
    else:
        print(f"  FAILURE: Found {errors} mismatches.")

def verify_indices():
    print("\nVerifying Sorted Indices...")
    # This is tricky because Python sort might differ slightly from 
    # C/SystemVerilog if values are exactly equal (stability).
    # Ideally, we just check if it IS sorted.
    
    # 1. Load Priors
    try:
        priors = np.loadtxt(ORIGINAL_FILES["Priors"])
    except:
        return

    # 2. Load Sorted Indices
    try:
        indices = np.loadtxt(FORMATTED_FILES["Indices"], dtype=int)
    except:
        return
        
    # 3. Check logic
    # Retrieve the priors using the indices
    sorted_priors = priors[indices]
    
    # Check if this array is actually sorted (Ascending)
    # (i.e., is every element <= the next element?)
    is_sorted = np.all(sorted_priors[:-1] <= sorted_priors[1:])
    
    if is_sorted:
        print("  SUCCESS: Indices map to a correctly sorted list.")
    else:
        print("  FAILURE: Indices do NOT produce a sorted list.")

if __name__ == "__main__":
    verify_h_matrix()
    verify_syndromes()
    verify_golden()
    verify_indices()