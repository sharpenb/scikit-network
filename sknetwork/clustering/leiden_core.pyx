# distutils: language = c++
# cython: language_level=3
# cython: linetrace=True
# distutils: define_macros=CYTHON_TRACE_NOGIL=1
from libcpp.set cimport set
from libcpp.vector cimport vector
from libcpp.queue cimport queue
cimport cython


@cython.boundscheck(False)
@cython.wraparound(False)
def fit_core(float resolution, float tol, float[:] ou_node_probs, float[:] in_node_probs, float[:] self_loops,
             float[:] data, int[:] indices, int[:] indptr, int[:] labels_array):  # pragma: no cover
    """Fit the clusters to the objective function.

    Parameters
    ----------
    resolution :
        Resolution parameter (positive).
    tol :
        Minimum increase in modularity to enter a new optimization pass.
    ou_node_probs :
        Distribution of node weights based on their out-edges (sums to 1).
    in_node_probs :
        Distribution of node weights based on their in-edges (sums to 1).
    self_loops :
        Weights of self loops.
    data :
        CSR format data array of the normalized adjacency matrix.
    indices :
        CSR format index array of the normalized adjacency matrix.
    indptr :
        CSR format index pointer array of the normalized adjacency matrix.

    Returns
    -------
    labels :
        Cluster index of each node.
    total_increase :
        Score of the clustering (total increase in modularity).
    """
    cdef int n = indptr.shape[0] - 1
    cdef int increase = 1
    cdef int cluster
    cdef int cluster_best
    cdef int cluster_node
    cdef int i
    cdef int j
    cdef int j1
    cdef int j2
    cdef int label

    cdef float increase_total = 0
    cdef float increase_pass
    cdef float delta
    cdef float delta_best
    cdef float delta_exit
    cdef float delta_local
    cdef float node_prob_in
    cdef float node_prob_ou
    cdef float ratio_in
    cdef float ratio_ou

    cdef queue[int] nodes
    cdef vector[int] labels
    cdef vector[float] neighbor_clusters_weights
    cdef vector[float] ou_clusters_weights
    cdef vector[float] in_clusters_weights
    cdef set[int] unique_clusters = ()
    cdef set[int] queue_elements = ()

    for i in range(n):
        nodes.push(i)
        queue_elements.insert(i)
        labels.push_back(labels_array[i])
        neighbor_clusters_weights.push_back(0.)
        ou_clusters_weights.push_back(ou_node_probs[i])
        in_clusters_weights.push_back(in_node_probs[i])

    while not nodes.empty():
        increase_pass = 0

        i = nodes.front()
        nodes.pop()
        queue_elements.erase(i)
        unique_clusters.clear()
        cluster_node = labels[i]
        j1 = indptr[i]
        j2 = indptr[i + 1]

        for j in range(j1, j2):
            label = labels[indices[j]]
            neighbor_clusters_weights[label] += data[j]
            unique_clusters.insert(label)

        unique_clusters.erase(cluster_node)

        if not unique_clusters.empty():
            node_prob_ou = ou_node_probs[i]
            node_prob_in = in_node_probs[i]
            ratio_ou = resolution * node_prob_ou
            ratio_in = resolution * node_prob_in

            delta_exit = 2 * (neighbor_clusters_weights[cluster_node] - self_loops[i])
            delta_exit -= ratio_ou * (in_clusters_weights[cluster_node] - node_prob_in)
            delta_exit -= ratio_in * (ou_clusters_weights[cluster_node] - node_prob_ou)

            delta_best = 0
            cluster_best = cluster_node

            for cluster in unique_clusters:
                delta = 2 * neighbor_clusters_weights[cluster]
                delta -= ratio_ou * in_clusters_weights[cluster]
                delta -= ratio_in * ou_clusters_weights[cluster]

                delta_local = delta - delta_exit
                if delta_local > delta_best:
                    delta_best = delta_local
                    cluster_best = cluster

                neighbor_clusters_weights[cluster] = 0

            if delta_best > 0:
                increase_pass += delta_best
                ou_clusters_weights[cluster_node] -= node_prob_ou
                in_clusters_weights[cluster_node] -= node_prob_in
                ou_clusters_weights[cluster_best] += node_prob_ou
                in_clusters_weights[cluster_best] += node_prob_in
                labels[i] = cluster_best
                for j in range(j1, j2):
                    if labels[indices[j]] != cluster_best and queue_elements.find(indices[j]) == queue_elements.end():
                        queue_elements.insert(indices[j])
                        nodes.push(indices[j])


        neighbor_clusters_weights[cluster_node] = 0

        increase_total += increase_pass
    return labels, increase_total