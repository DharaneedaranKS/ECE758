from common.build_circuit import dem_to_check_matrices, build_circuit
from common.codes_q import create_bivariate_bicycle_codes
import stim
from typing import Tuple
import numpy as np

def gen(p:float, basis:str='Z') -> stim.Circuit:
    # Only [[144, 12, 12]] code
    code, A_list, B_list = create_bivariate_bicycle_codes(12, 6, [3], [1,2], [1,2], [3])
    circuit = build_circuit(code, A_list, B_list, p=p,
                            num_repeat=12, use_both=False, 
                            z_basis=(basis.lower() == 'z'))
    return circuit

def gen_d18(p:float, basis:str='Z') -> stim.Circuit:
    # Only [[144, 12, 12]] code
    code, A_list, B_list = create_bivariate_bicycle_codes(12, 12, [3], [2,7], [1,2], [3])
    d = 18
    circuit = build_circuit(code, A_list, B_list, p=p,
                            num_repeat=d, use_both=False, 
                            z_basis=(basis.lower() == 'z'))
    return circuit

def get_params(circuit:stim.Circuit) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    chk, obs, priors, _ = dem_to_check_matrices(circuit.detector_error_model(), return_col_dict=True)
    return chk.toarray(), obs.toarray(), priors