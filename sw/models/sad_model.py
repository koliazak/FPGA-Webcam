import numpy as np


def cost_volume(L: np.ndarray, R: np.ndarray, min_disp, D: int):
    """|L(y,x) - R(y,x-d)| for d = min_disp + k, k = 0..D-1.
    Returns int32 (D, H, W); x - d < 0 -> 0."""
    assert L.shape == R.shape    
    
    H,W = L.shape
    result = np.stack([L]*D).astype(np.int32)
    
    for k in range(D):
        d = min_disp + k
        result[k, :, d:] -= R[:, :W-d]
        result[k, :, :d] = 0

    return np.abs(result)


def _window_sums_slow(cost: np.ndarray, window: int):
    assert window % 2 == 1, "Window must be odd"

    r = window // 2 # "radius"
    result = np.zeros_like(cost)
    D, H, W = cost.shape

    for k in range(D):
        cur_cost = cost[k] # [H,W]

        for h in range(r, H-r):
            for w in range(r, W-r):
                cur_window = cur_cost[h-r:h+r+1,w-r:w+r+1]
                result[k,h,w] = np.sum(cur_window)
    return result


def window_sums(cost: np.ndarray, window: int):
    assert window % 2 == 1, "Window must be odd"

    r = window // 2 # "radius"
    D, H, W = cost.shape

    C = np.zeros_like(cost)
    S = np.zeros_like(cost)

    C[:,r,:] = cost[:,0:window,:].sum(axis=1)

    for y in range(r+1, H-r):
        C[:,y,:] = C[:,y-1,:] + cost[:,y+r,:] - cost[:,y-r-1,:]


    S[:,:,r] = C[:,:,0:window].sum(axis=2)
    for x in range(r+1, W-r):
        S[:,:,x] = S[:,:,x-1] + C[:,:,x+r] - C[:,:,x-r-1]
    
    return S

def select(S, min_disp, K) -> np.ndarray:
    
    # argmin
    k_best = np.argmin(S, axis=0)
    S_min  = np.min(S, axis=0)
    

    if K > 0:
        # K/128 corresponds to uniquenessRatio/100  
        thresh = S_min + ((S_min * K) >> 7)

        ks = np.arange(S.shape[0])[:, None, None] # (D, 1, 1)

        far = np.abs(ks - k_best[None]) > 1
        close = S <= thresh[None]

        ambiguous = (far & close).any(axis=0) 
    else:
        ambiguous = np.zeros(S.shape[1:], dtype=bool)
    
    assert min_disp >= 1
    assert min_disp + S.shape[0] - 1 <= 255
    disp = (min_disp + k_best).astype(np.uint8) * ~ambiguous # zeros on invalid depth
    return disp


def valid_mask(H, W, min_disp, D, win):
    valid = np.zeros((H, W), dtype=bool)
    r = win // 2

    valid[r:H-r, r+D+min_disp-1:W-r] = True    
    return valid


