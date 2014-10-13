volumetricRGC
=============

This repository includes code and data used in U. Sümbül et al.,
``Automated computation of arbor densities: a step toward identifying
neuronal cell types,'' Frontiers in Neuroanatomy, 2014.

The arbor traces are based on the raw image stacks, except for two files
which are based on a basic deformation of the volume, as indicated by the
file names. For details, please refer to github.com/uygarsumbul/rgc, which
contains neurons from a more heterogeneous dataset as well. The dataset
used in this paper is a subset of that dataset. The traces use voxel
coordinates where the voxel size is 0.4um x 0.4 um x 0.5 um. For trace
files using physical coordinates, please see github.com/uygarsumbul/rgc.

The SAC surface files contain the automatically detected starburst amacrine
cell arbor positions. The variable minmesh (maxmesh) contains the depth
coordinate of the On (Off) SAC surface for each xy pair. The values are in
pixel coordinates.

The reconstruction files contain the coordinates of the voxels belonging to
the neurons and the depth profiles. The variable 'voxels' contains the physical
coordinates of the voxels of the 3d trace-based reconstructions of the neurons.
The values are in um, where the depth values (voxels(:,:,3)) use the common
depth coordinate, for which the distance between the On (0um) and Off (12um)
SAC surfaces is 12um, as described in the paper.

The variable 'zDstribution' contains the registered depth profile in the
interval [-30um, 29.5um] with a step size of 0.5um. The sum of the variable
gives the volume of the reconstruction in um^3.

Only the software that is not already posted in github.com/uygarsumbul/rgc
is posted in this repository.

Genetic identities of neurons:
Image100-XXX : BDa
Image101-XXX : BDa

Image102-XXX : JAM-B
Image104-XXX : JAM-B

Image120-XXX : W3
Image121-XXX : W3
Image122-XXX : W3
