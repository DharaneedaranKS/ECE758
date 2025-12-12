from ldpc.bposd_decoder import BpOsdDecoder
from ldpc.bp_decoder import BpDecoder
from union_find import lse_solver
import numpy as np
import pickle
from circuit_gen import gen, get_params, gen_d18
import ray
from itertools import product
import argparse

ray.init(num_cpus=32)

@ray.remote
def osd(det, observable, d, p, basis, ts):
    circuit = gen(p=p, basis=basis) if d != 18 else gen_d18(p=p, basis=basis)
    chk, obs, priors = get_params(circuit)
    bposd = BpOsdDecoder(
        chk,
        error_channel=list(priors),
        max_iter=100,
        input_vector_type='syndrome',
        osd_method='OSD_0',
        osd_order=0
    )
    ehat_osd0 = bposd.decode(det)
    error_osd0 = np.any(((obs @ ehat_osd0) + observable) % 2)
    return error_osd0

@ray.remote
def osd_prime(det, observable, d, p, basis, ts):
    circuit = gen(p=p, basis=basis) if d != 18 else gen_d18(p=p, basis=basis)
    chk, obs, priors = get_params(circuit)
    bpd = BpDecoder(chk, error_channel=list(priors), 
                    max_iter=100, input_vector_type='syndrome')
    e_hat = bpd.decode(det)
    # bposd = BpOsdDecoder(
    #     chk,
    #     error_channel=list(priors),
    #     max_iter=100,
    #     input_vector_type='syndrome',
    #     osd_method='OSD_0',
    #     osd_order=0
    # )
    cycles = 0
    # ehat_osd0 = bposd.decode(det)
    # error_osd0 = np.any(((obs @ ehat_osd0) + observable) % 2)
    error_osd0 = None
    llrs = bpd.log_prob_ratios
    t1, t2 = ts
    sorted_llrs_idx = np.argsort(llrs)
    sorted_llrs = llrs[sorted_llrs_idx]
    permuted_chk = chk[:, sorted_llrs_idx]
    cols = np.where(sorted_llrs <= t2)[0]
    cycles += len(llrs) // 16 # + len(cols) # n/16 cycles *8 banks, dual port* for scanning and truncating, cols cycles for sorting
    # print('Number of columns selected: ', len(cols), 't2: ', t2)
    A = permuted_chk[:, cols]
    all_zero_rows = len(np.where(np.all(A == 0, axis=1))[0])
    b = det # (det + (chk @ e_hat)) % 2
    solver = lse_solver()
    if len(cols) > 1000:
        return True, error_osd0, False, cycles, len(cols), all_zero_rows
    x = solver.solve(A, b)
    # cycles += solver.cycles
    # cycles += 3 * len(cols) + chk.shape[0] + 1 - 2
    if x is None:
        return True, error_osd0, False, cycles, len(cols), all_zero_rows
    _e_hat = np.zeros_like(e_hat, dtype=np.bool_)
    _e_hat[sorted_llrs_idx[cols]] = x
    cycles += len(cols) // 2 # n/2 cycles for re-permuting
    error = np.any(((obs @ _e_hat) + observable) % 2)
    match = False # np.array_equal(_e_hat, ehat_osd0)
    return error, error_osd0, match, cycles, len(cols), all_zero_rows
    # print(A.shape, x.shape, b.shape, det.shape)
    # print('LSE success:', np.array_equal((chk @ _e_hat) % 2, det))
    # print('logical error: ', np.any((obs @ _e_hat) + observable) % 2)
    
@ray.remote
def osd_prime_2(det, observable, chk, obs, priors, ts):
    bpd = BpDecoder(chk, error_channel=list(priors), 
                    max_iter=100, input_vector_type='syndrome')
    e_hat = bpd.decode(det)
    bposd = BpOsdDecoder(
        chk,
        error_channel=list(priors),
        max_iter=100,
        input_vector_type='syndrome',
        osd_method='OSD_0',
        osd_order=0
    )
    ehat_osd0 = bposd.decode(det)
    error_osd0 = np.any(((obs @ ehat_osd0) + observable) % 2)
    llrs = bpd.log_prob_ratios
    t1, t2 = ts
    cols = np.where(llrs <= t2)[0]
    # print('Number of columns selected: ', len(cols), 't2: ', t2)
    A = chk[:, cols]
    b = det # (det + (chk @ e_hat)) % 2
    solver = lse_solver()
    x = solver.solve(A, b)
    cycles = solver.cycles
    if x is None:
        return True, error_osd0, False, cycles
    _e_hat = np.zeros_like(e_hat, dtype=np.bool_)
    _e_hat[cols] = x
    error = np.any(((obs @ _e_hat) + observable) % 2)
    match = np.array_equal(_e_hat, ehat_osd0)
    return error, error_osd0, match, cycles

@ray.remote
def osd_prime_3(det, observable, chk, obs, priors, ts):
    bpd = BpDecoder(chk, error_channel=list(priors), 
                    max_iter=100, input_vector_type='syndrome')
    e_hat = bpd.decode(det)
    bposd = BpOsdDecoder(
        chk,
        error_channel=list(priors),
        max_iter=100,
        input_vector_type='syndrome',
        osd_method='OSD_0',
        osd_order=0
    )
    ehat_osd0 = bposd.decode(det)
    t1, t2 = ts
    error_osd0 = np.any(((obs @ ehat_osd0) + observable) % 2)
    llrs = bpd.log_prob_ratios
    A = None
    all_cols = []
    cutoffs = [-1000, -100, -10, 0, 10, 100, 1000, t2]
    for i, cutoff in enumerate(cutoffs):
        if i == 0:
            cols = np.where(llrs <= cutoff)[0]
        else:
            cols = np.where((llrs <= cutoff) & (llrs > cutoffs[i-1]))[0]
        if A is None:
            A = chk[:, cols]
        else:
            A = np.hstack((A, chk[:, cols]))
        all_cols += cols.tolist()
        pass
    b = det
    solver = lse_solver()
    x = solver.solve(A, b)
    cycles = solver.cycles
    if x is None:
        return True, error_osd0, False, cycles
    _e_hat = np.zeros_like(e_hat, dtype=np.bool_)
    _e_hat[all_cols] = x
    error = np.any(((obs @ _e_hat) + observable) % 2)
    match = np.array_equal(_e_hat, ehat_osd0)
    return error, error_osd0, match, cycles

@ray.remote
def _sweep(det, observable, t, d, p, basis):
    circuit = gen(p=p, basis=basis) if d != 18 else gen_d18(p=p, basis=basis)
    chk, obs, priors = get_params(circuit)
    bpd = BpDecoder(chk, error_channel=list(priors),
                    max_iter=100, input_vector_type='syndrome')
    e_hat = bpd.decode(det)
    llrs = bpd.log_prob_ratios
    sorted_llrs_idx = np.argsort(llrs)
    sorted_llrs = llrs[sorted_llrs_idx]
    permuted_chk = chk[:, sorted_llrs_idx]
    cols = np.where(sorted_llrs <= t)[0]
    # print('Number of columns selected: ', len(cols), 't2: ', t2)
    A = permuted_chk[:, cols]
    b = det # (det + (chk @ e_hat)) % 2
    solver = lse_solver()
    x = solver.solve(A, b)
    cycles = solver.cycles
    if x is None:
        return True, cycles
    _e_hat = np.zeros_like(e_hat, dtype=np.bool_)
    _e_hat[sorted_llrs_idx[cols]] = x
    error = np.any(((obs @ _e_hat) + observable) % 2)
    return error, cycles

@ray.remote
def _sweep_approx(det, observable, t):
    chk, obs, priors = get_params(gen(0.001, 'Z'))
    bpd = BpDecoder(chk, error_channel=list(priors),
                    max_iter=100, input_vector_type='syndrome')
    e_hat = bpd.decode(det)
    llrs = bpd.log_prob_ratios
    A = None
    all_cols = []
    cutoffs = [-100, -50, -10, 0, 10] + [i if 50 < t else t for i in [50, 100]]
    for i, cutoff in enumerate(cutoffs):
        if i == 0:
            cols = np.where(llrs <= cutoff)[0]
        else:
            cols = np.where((llrs <= cutoff) & (llrs > cutoffs[i-1]))[0]
        if A is None:
            A = chk[:, cols]
        else:
            A = np.hstack((A, chk[:, cols]))
        all_cols += cols.tolist()
        pass
    b = det
    solver = lse_solver()
    x = solver.solve(A, b)
    cycles = solver.cycles
    if x is None:
        return True, cycles
    _e_hat = np.zeros_like(e_hat, dtype=np.bool_)
    _e_hat[all_cols] = x
    error = np.any(((obs @ _e_hat) + observable) % 2)
    return error, cycles

def run(file:str, lconf:int=30):
    with open(file, 'rb') as f:
        data = pickle.load(f)
    if len(data) == 5:
        dets, observables, priors, mean_error, errors = data
    else:
        dets, observables = data
    splits = file.split('_')
    basis = splits[1]
    p = float(splits[2].replace('.pkl', ''))
    d = int(splits[3].replace('.pkl', '').replace('d', '')) if len(splits) == 4 else 12
    futures = []
    for det, observable in zip(dets, observables):
        futures.append(osd_prime.remote(det, observable, d, p, basis, (-lconf, lconf)))
    num_total = len(futures)
    num_finished = 0
    results = [None] * num_total
    remaining = futures.copy()
    while remaining:
        done, remaining = ray.wait(remaining, num_returns=1)
        idx = futures.index(done[0])
        results[idx] = ray.get(done[0])
        num_finished += 1
        print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')
    with open(f'osd_results_{basis}_{d}_{p}_{lconf}.pkl', 'wb') as f:
        pickle.dump(results, f)
    pass

def run_osd(file:str, lconf:int=30):
    with open(file, 'rb') as f:
        data = pickle.load(f)
    if len(data) == 5:
        dets, observables, priors, mean_error, errors = data
    else:
        dets, observables = data
    splits = file.split('_')
    basis = splits[1]
    p = float(splits[2].replace('.pkl', ''))
    d = int(splits[3].replace('.pkl', '').replace('d', '')) if len(splits) == 4 else 12
    futures = []
    for det, observable in zip(dets, observables):
        futures.append(osd.remote(det, observable, d, p, basis, (-lconf, lconf)))
    num_total = len(futures)
    num_finished = 0
    results = [None] * num_total
    remaining = futures.copy()
    while remaining:
        done, remaining = ray.wait(remaining, num_returns=1)
        idx = futures.index(done[0])
        results[idx] = ray.get(done[0])
        num_finished += 1
        print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')
    with open(f'osd0_results_{basis}_{d}_{p}.pkl', 'wb') as f:
        pickle.dump(results, f)
    print('OSD0: ', np.mean([res for res in results]))
    pass

def sweep(file:str='./unconverged_Z_0.001.pkl', t1_start:int=-1000, t2_start:int=200):
    # t1s = range(t1_start, -1, 10)
    # t2s = range(t2_start, -1, -10)
    # ts = [(t1, t2) for t1, t2 in zip(t1s, t2s)]
    t2s = [500, 250, 100, 75, 50, 40, 30, 25, 20, 15]
    with open(file, 'rb') as f:
        data = pickle.load(f)
    if len(data) == 5:
        dets, observables, priors, mean_error, errors = data
    else:
        dets, observables = data
    splits = file.split('_')
    basis = splits[1]
    p = float(splits[2].replace('.pkl', ''))
    d = int(splits[3].replace('.pkl', '').replace('d', '')) if len(splits) == 4 else 12
    futures = []
    exps = list(product(zip(dets[:2500], observables[:2500]), t2s, [d], [p], [basis]))
    for (det, observable), t2, _d, _p, _basis in exps:
        futures.append(_sweep.remote(det, observable, t2, _d, _p, _basis))
    num_total = len(futures)
    num_finished = 0
    results = [None] * num_total
    remaining = futures.copy()
    while remaining:
        done, remaining = ray.wait(remaining, num_returns=1)
        idx = futures.index(done[0])
        results[idx] = ray.get(done[0])
        num_finished += 1
        print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')

    all_results = {t2: [] for t2 in t2s}
    for i, result in enumerate(results):
        t2 = exps[i][1]
        all_results[t2].append(result)
    return all_results

def sweep_approx(file:str='./unconverged_Z_0.001.pkl', t1_start:int=-1000, t2_start:int=200):
    # t1s = range(t1_start, -1, 10)
    # t2s = range(t2_start, -1, -10)
    # ts = [(t1, t2) for t1, t2 in zip(t1s, t2s)]
    t2s = [500, 250, 100, 75, 50, 40, 30, 25, 20, 15]
    with open(file, 'rb') as f:
        data = pickle.load(f)
    dets, observables, priors, mean_error, errors = data
    futures = []
    exps = list(product(zip(dets[:2500], observables[:2500]), t2s))
    for (det, observable), t2 in exps:
        futures.append(_sweep_approx.remote(det, observable, t2))
    num_total = len(futures)
    num_finished = 0
    results = [None] * num_total
    remaining = futures.copy()
    while remaining:
        done, remaining = ray.wait(remaining, num_returns=1)
        idx = futures.index(done[0])
        results[idx] = ray.get(done[0])
        num_finished += 1
        print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')

    all_results = {t2: [] for t2 in t2s}
    for i, result in enumerate(results):
        t2 = exps[i][1]
        all_results[t2].append(result)
    return all_results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run BPUF decoder with specified parameters')
    parser.add_argument('--file', type=str, help='Filename of the pickle file containing detector data')
    parser.add_argument('--lconf', type=float, default=30, help='confidence threshold for OSD')
    parser.add_argument('--sweep', action='store_true', help='whether to run sweep or not')
    args = parser.parse_args()
    file = args.file
    lconf = args.lconf
    if args.sweep:
        results = sweep(file=file)
        with open(f'threshold_osd_prime_{file}.pkl', 'wb') as f:
            pickle.dump(results, f)
            
        # results = sweep_approx()
        # with open(f'threshold_osd_prime_approx_{file}.pkl', 'wb') as f:
        #     pickle.dump(results, f)
    else:
        run(file, lconf)
        pass
    # print('--------------------- Running OSD\' without permutation ---------------------')

    # with open('./unconverged_Z_0.001.pkl', 'rb') as f:
    #     data = pickle.load(f)

    # t1, t2 = -20, 10000
    # dets, observables, priors, mean_error, errors = data
    # chk, obs, priors = get_params(gen(0.001, 'Z'))
    # futures = []
    # for i in range(len(dets)):
    #     det, observable = dets[i], observables[i]
    #     futures.append(osd_prime_2.remote(det, observable, chk, obs, priors, (t1, t2)))
    # remaining = futures.copy()
    # num_total = len(futures)
    # num_finished = 0
    # results = [None] * num_total
    # while remaining:
    #     done, remaining = ray.wait(remaining, num_returns=1)
    #     idx = futures.index(done[0])
    #     results[idx] = ray.get(done[0])
    #     num_finished += 1
    #     print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')
    # all_results = {'osd_prime2_error': [], 'osd0_error': [], 'match': [], 'cycles': []}
    # for i, result in enumerate(results):
    #     error, error_osd0, match, cycles = result
    #     all_results['osd_prime2_error'].append(error)
    #     all_results['osd0_error'].append(error_osd0)
    #     all_results['match'].append(match)
    #     all_results['cycles'].append(cycles)
    # with open('osd_prime2_results.pkl', 'wb') as f:
    #     pickle.dump(all_results, f)
    # print('Results for OSD\' without permutation: ')
    # print('\t OSD\' logical error rate: ', np.mean(all_results['osd_prime2_error']))
    # print('\t OSD0 logical error rate: ', np.mean(all_results['osd0_error']))
    # print('\t Match rate between OSD\' and OSD0: ', np.mean(all_results['match']))
    
    # print('--------------------- Running OSD\' ---------------------')
    # with open('./unconverged_Z_0.001.pkl', 'rb') as f:
    #     data = pickle.load(f)

    # t1, t2 = -20, 10000
    # dets, observables, priors, mean_error, errors = data
    # chk, obs, priors = get_params(gen(0.001, 'Z'))
    # futures = []
    # for i in range(len(dets)):
    #     det, observable = dets[i], observables[i]
    #     futures.append(osd_prime.remote(det, observable, chk, obs, priors, (t1, t2)))
    # remaining = futures.copy()
    # num_total = len(futures)
    # num_finished = 0
    # results = [None] * num_total
    # while remaining:
    #     done, remaining = ray.wait(remaining, num_returns=1)
    #     idx = futures.index(done[0])
    #     results[idx] = ray.get(done[0])
    #     num_finished += 1
    #     print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')
    # all_results = {'osd_prime_error': [], 'osd0_error': [], 'match': [], 'cycles': []}
    # for i, result in enumerate(results):
    #     error, error_osd0, match, cycles = result
    #     all_results['osd_prime_error'].append(error)
    #     all_results['osd0_error'].append(error_osd0)
    #     all_results['match'].append(match)
    #     all_results['cycles'].append(cycles)
    # with open('osd_prime_results.pkl', 'wb') as f:
    #     pickle.dump(all_results, f)
    # print('Results for OSD\' with permutation: ')
    # print('\t OSD\' logical error rate: ', np.mean(all_results['osd_prime_error']))
    # print('\t OSD0 logical error rate: ', np.mean(all_results['osd0_error']))
    # print('\t Match rate between OSD\' and OSD0: ', np.mean(all_results['match']))
    
    # print('--------------------- Running OSD\' without permutation, with binning ---------------------')

    # with open('./unconverged_Z_0.001.pkl', 'rb') as f:
    #     data = pickle.load(f)

    # t1, t2 = -20, 10000
    # dets, observables, priors, mean_error, errors = data
    # chk, obs, priors = get_params(gen(0.001, 'Z'))
    # futures = []
    # for i in range(len(dets)):
    #     det, observable = dets[i], observables[i]
    #     futures.append(osd_prime_3.remote(det, observable, chk, obs, priors, (t1, t2)))
    # remaining = futures.copy()
    # num_total = len(futures)
    # num_finished = 0
    # results = [None] * num_total
    # while remaining:
    #     done, remaining = ray.wait(remaining, num_returns=1)
    #     idx = futures.index(done[0])
    #     results[idx] = ray.get(done[0])
    #     num_finished += 1
    #     print(f"Progress: {num_finished}/{num_total} tasks finished, {len(remaining)} in flight.", end='\r')
    # all_results = {'osd_prime3_error': [], 'osd0_error': [], 'match': [], 'cycles': []}
    # for i, result in enumerate(results):
    #     error, error_osd0, match, cycles = result
    #     all_results['osd_prime3_error'].append(error)
    #     all_results['osd0_error'].append(error_osd0)
    #     all_results['match'].append(match)
    #     all_results['cycles'].append(cycles)
    # with open('osd_prime3_results.pkl', 'wb') as f:
    #     pickle.dump(all_results, f)
    # print('Results for OSD\' without permutation: ')
    # print('\t OSD\' logical error rate: ', np.mean(all_results['osd_prime3_error']))
    # print('\t OSD0 logical error rate: ', np.mean(all_results['osd0_error']))
    # print('\t Match rate between OSD\' and OSD0: ', np.mean(all_results['match']))
    
# --------------------- Running OSD' without permutation ---------------------
# Results for OSD' without permutation: in flight....
#          OSD' logical error rate:  0.1882498965659909
#          OSD0 logical error rate:  0.0028961522548613984
#          Match rate between OSD' and OSD0:  0.02689284236657013
# --------------------- Running OSD' ---------------------
# Results for OSD' with permutation:  0 in flight....         
#          OSD' logical error rate:  0.0028961522548613984
#          OSD0 logical error rate:  0.0028961522548613984
#          Match rate between OSD' and OSD0:  0.9755895738518825
# --------------------- Running OSD' without permutation, with binning ---------------------
# Results for OSD' without permutation: in flight....
#          OSD' logical error rate:  0.007447248655357882
#          OSD0 logical error rate:  0.0028961522548613984
#          Match rate between OSD' and OSD0:  0.34133223003723623