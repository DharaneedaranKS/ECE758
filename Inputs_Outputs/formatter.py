import os
import numpy as np

# Configuration
INPUT_FILES = {
    "H": "H_matrix.txt",
    "Priors": "priors.txt",
    "Syndromes": "dets_0_1.txt",
    "Golden": "golden_e_all.txt"
}

OUTPUT_DIR = "formatted_tests"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def process_h_matrix():
    print("Processing H_matrix.txt...")
    # Input: Space-separated ints. Usually 936 rows x 8784 cols.
    # Goal: We need to write 8784 lines, where each line is a 936-bit COLUMN.
    #       This requires TRANSPOSING the matrix.
    
    try:
        # Load the entire matrix into numpy (shape: 936 x 8784)
        print("  Loading matrix into memory...")
        H = np.loadtxt(INPUT_FILES["H"], dtype=int)
        
        # Verify shape
        rows, cols = H.shape
        print(f"  Matrix shape detected: {rows} rows x {cols} cols")
        
        # Transpose so we can iterate by column (shape: 8784 x 936)
        H_T = H.T
        
        # Write out line-by-line
        print("  Writing transposed formatted file...")
        with open(f'{OUTPUT_DIR}/H_matrix_formatted.txt', 'w') as f_out:
            # H_T is now [col_index][row_index]
            # When we iterate H_T, we get the columns of the original H
            for col_vector in H_T:
                # Convert [0, 1, 1...] array to dense string "011..."
                # Orientation: Element 0 (Row 0) becomes the first char of string.
                # In Verilog $fscanf("%b"), first char -> MSB.
                # Inverter needs Row 0 at MSB. This matches.
                dense_line = "".join(map(str, col_vector))
                f_out.write(dense_line + "\n")
                
    except Exception as e:
        print(f"Error processing H matrix: {e}")

def process_priors():
    print("Processing priors.txt...")
    # Input: One float per line. 8784 lines.
    # Output: Sorted INDICES (0 to 8783).
    # Sort Order: Ascending (Smallest Prob of Error = Most Reliable = First Index).
    
    try:
        priors = np.loadtxt(INPUT_FILES["Priors"])
    except Exception as e:
        print(f"Error reading priors: {e}")
        return

    # argsort returns the indices that would sort the array
    sorted_indices = np.argsort(priors)
    
    # Save as integers, one per line
    np.savetxt(f'{OUTPUT_DIR}/sorted_indices.txt', sorted_indices, fmt='%d')

def process_syndromes():
    print("Processing dets_0_1.txt...")
    # Input: Space-separated ints.
    # Alignment: We want Loop Index 0 -> File Element 0.
    # In Verilog, Index 0 is LSB. 
    # String "e0e1..." puts e0 at MSB.
    # So we MUST REVERSE the list to put e0 at LSB.
    
    with open(INPUT_FILES["Syndromes"], 'r') as f_in, open(f'{OUTPUT_DIR}/syndromes_formatted.txt', 'w') as f_out:
        for line in f_in:
            bits = line.split()
            if not bits: continue
            
            # Reverse list so Element 0 becomes LSB (String end)
            bits.reverse()
            
            dense_line = "".join(bits)
            f_out.write(dense_line + "\n")

def process_golden():
    print("Processing golden_e_all.txt...")
    # Input: Dense string "00100...".
    # Alignment: We want Error Index 0 -> File Element 0.
    # In Verilog, Index 0 is LSB.
    # So we MUST REVERSE the string to put e0 at LSB.
    
    with open(INPUT_FILES["Golden"], 'r') as f_in, open(f'{OUTPUT_DIR}/golden_formatted.txt', 'w') as f_out:
        for line in f_in:
            line = line.strip()
            if not line: continue
            
            # Reverse string
            reversed_line = line[::-1]
            
            f_out.write(reversed_line + "\n")

if __name__ == "__main__":
    process_h_matrix()
    process_priors()
    process_syndromes()
    process_golden()
    print("Done! Files are in 'formatted_tests/'")