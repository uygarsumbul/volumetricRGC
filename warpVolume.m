function [voxels zDistribution] = warpVolume(vol, OnSACFilename, OffSACFilename, sacFittingBoundaries, resolution, conformalJump)
% Software developed by: Uygar Sümbül <uygar@stat.columbia.edu, uygar@mit.edu> unless otherwise indicated in the function headers
% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.
% IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DAMAGES WHATSOEVER.
%
% Warp the contents of a binary 3-d image stack by quasi-conformally mapping the starburst surfaces into flat surfaces

% -- vol is the binary 3d volume
% -- OnSACFileName, OffSACFilename - annotation files for starburst surfaces (Refer to Sümbül et al., Nat. Commun., 2014
%    and github.com/uygarsumbul/rgc/ for examples)
% -- sacFittingBoundaries: [minXpos maxXpos minYpos maxYpos] - 2d bounding box (voxel units) over which fitting/warping will be performed.
%    Picking a tighter box including the arbor improves the fit when starburst surfaces are not healthy/reliable outside the box.
% -- resolution: [x y z] - physical resolution in microns
% -- conformalJump: positive integer. 1 for exact, slow calculations. In practice, 2 or 3 produce accurate results much faster

%generate the SAC surfaces from annotations
thisVZminmesh = fitSurfaceToSACAnnotation(OnSACFilename);
thisVZmaxmesh = fitSurfaceToSACAnnotation(OffSACFilename);
% find conformal maps of the ChAT surfaces onto the median plane
surfaceMapping = calcWarpedSACsurfaces(thisVZminmesh,thisVZmaxmesh,sacFittingBoundaries,conformalJump);
% warp the non-zero (true) voxels in the volume
warpedVoxels = calcWarpedVoxels(vol,surfaceMapping,resolution,conformalJump);
if any(isnan(warpedVoxels.voxels(:))); disp('Something went wrong with voxel warping - Check the boundaries and units!'); end;
% determine individual voxel weights ('mass') assuming density becomes uniform after warping
% weight is the cube of the median distance to 6-neighbors in the object
weights = zeros(size(warpedVoxels.voxels,1),1);
for kk = 1:size(warpedVoxels.voxels,1)
  if numel(warpedVoxels.neighborList{kk})<1
    weights(kk) = 1;
  else
    weights(kk) = median(sqrt(sum((kron(warpedVoxels.voxels(kk,:),ones(numel(neighborList{kk}),1))-voxels(neighborList{kk},:)).^2,2)))^3;
  end
end
% use physical dimensions (in um)
voxels(:,1) = voxels(:,1)*resolution(1); voxels(:,2) = voxels(:,2)*resolution(2); voxels(:,3) = voxels(:,3)*resolution(3);
% switch to SAC based system, assuming that the distance between SAC planes is 12um
medVzmin = median(tmpminmesh(:)); medVzmax = median(tmpmaxmesh(:));
allZpos = (2*voxels(:,3) - medVzmin)/(medVzmax - medVzmin)/5;
% use the weights found above in gridding
zDistribution = pureGridder1d(allZpos,weights,120);
% sum of zDistribution gives the volume in um^3
zDistribution = zDistribution * (sum(weights)*prod(resolution)/sum(zDistribution));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function vzmesh = fitSurfaceToSACAnnotation(annotationFilename)
% read the annotation file
[t1,t2,t3,t4,t5,x,z,y] = textread(annotationFilename, '%u%u%d%d%d%d%d%d','headerlines',1);
% add 1 to x and z, butnot to y because FIJI point tool starts from 0 for pixels of an image
% but from 1 for slice of a stack
x=x+1; z=z+1;
% find the maximum boundaries
xMax = max(x); yMax = max(y);
% smoothened fit (with extrapolation) to a grid - to save time, make the grid coarser (every 3 pixels)
[zgrid,xgrid,ygrid] = gridfit(x,y,z,[[1:3:xMax-1] xMax],[[1:3:yMax-1] yMax],'smoothness',1);
% linearly (fast) interpolate to fine grid
[xi,yi]=meshgrid(1:xMax,1:yMax); xi = xi'; yi = yi';
vzmesh=interp2(xgrid,ygrid,zgrid,xi,yi,'*linear',mean(zgrid(:)));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function surfaceMapping = calcWarpedSACsurfaces(thisVZminmesh,thisVZmaxmesh,arborBoundaries,conformalJump)
minXpos = arborBoundaries(1); maxXpos = arborBoundaries(2); minYpos = arborBoundaries(3); maxYpos = arborBoundaries(4);
% retain the minimum grid of SAC points, where grid resolution is determined by conformalJump
thisx = [max(minXpos-1,1):conformalJump:min(maxXpos+1,size(thisVZmaxmesh,1))];
thisy = [max(minYpos-1,1):conformalJump:min(maxYpos+1,size(thisVZmaxmesh,2))];
thisminmesh=thisVZminmesh(thisx,thisy); thismaxmesh=thisVZmaxmesh(thisx,thisy);
% calculate the traveling distances on the diagonals of the two SAC surfaces - this must be changed to Dijkstra's algorithm for exact results
[mainDiagDistMin, skewDiagDistMin] = calculateDiagLength(thisx,thisy,thisminmesh);
[mainDiagDistMax, skewDiagDistMax] = calculateDiagLength(thisx,thisy,thismaxmesh);
% average the diagonal distances on both surfaces for more stability against band tracing errors - not ideal
mainDiagDist = (mainDiagDistMin+mainDiagDistMax)/2; skewDiagDist = (skewDiagDistMin+skewDiagDistMax)/2;
% quasi-conformally map individual SAC surfaces to planes
mappedMinPositions = conformalMap_indepFixedDiagonals(mainDiagDist,skewDiagDist,thisx,thisy,thisminmesh);
mappedMaxPositions = conformalMap_indepFixedDiagonals(mainDiagDist,skewDiagDist,thisx,thisy,thismaxmesh);
% align the two independently mapped surfaces so their flattest regions are registered to each other
xborders = [thisx(1) thisx(end)]; yborders = [thisy(1) thisy(end)];
mappedMaxPositions = alignMappedSurfaces(thisVZminmesh,thisVZmaxmesh,mappedMinPositions,mappedMaxPositions,xborders,yborders,conformalJump);
% return original and mapped surfaces with grid information
surfaceMapping.mappedMinPositions=mappedMinPositions; surfaceMapping.mappedMaxPositions=mappedMaxPositions;;
surfaceMapping.thisVZminmesh=thisVZminmesh; surfaceMapping.thisVZmaxmesh=thisVZmaxmesh; surfaceMapping.thisx=thisx; surfaceMapping.thisy=thisy;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [mainDiagDist, skewDiagDist] = calculateDiagLength(xpos,ypos,VZmesh)
M = size(VZmesh,1); N = size(VZmesh,2);
[ymesh,xmesh] = meshgrid(ypos,xpos);
mainDiagDist = 0; skewDiagDist = 0;
% travel on the diagonals and not necessarily the grid points) and accumulate the 3d distance traveled
if N >= M
  xKnots = interp2(ymesh,xmesh,xmesh, ypos, [xpos(1):(xpos(end)-xpos(1))/(N-1):xpos(end)]');
  yKnots = interp2(ymesh,xmesh,ymesh, ypos, [xpos(1):(xpos(end)-xpos(1))/(N-1):xpos(end)]');
  zKnotsMainDiag = griddata(xmesh(:),ymesh(:),VZmesh(:), [xpos(1):(xpos(end)-xpos(1))/(N-1):xpos(end)]', ypos');
  zKnotsSkewDiag = griddata(xmesh(:),ymesh(:),VZmesh(:), [xpos(1):(xpos(end)-xpos(1))/(N-1):xpos(end)]', ypos(end:-1:1)');
  dxKnots = diag(xKnots); dyKnots = diag(yKnots); mainDiagDist = sum(sqrt(diff(dxKnots).^2 + diff(dyKnots).^2 + diff(zKnotsMainDiag).^2));
  sdxKnots = xKnots(N:N-1:end-1)'; sdyKnots = yKnots(N:N-1:end-1)'; skewDiagDist = sum(sqrt(diff(sdxKnots).^2 + diff(sdyKnots).^2 + diff(zKnotsSkewDiag).^2));

else
  xKnots = interp2(ymesh,xmesh,xmesh, [ypos(1):(ypos(end)-ypos(1))/(M-1):ypos(end)], xpos');
  yKnots = interp2(ymesh,xmesh,ymesh, [ypos(1):(ypos(end)-ypos(1))/(M-1):ypos(end)], xpos');
  zKnotsMainDiag = griddata(xmesh(:),ymesh(:),VZmesh(:), xpos', [ypos(1):(ypos(end)-ypos(1))/(M-1):ypos(end)]');
  zKnotsSkewDiag = griddata(xmesh(:),ymesh(:),VZmesh(:), xpos', [ypos(end):-(ypos(end)-ypos(1))/(M-1):ypos(1)]');
  dxKnots = diag(xKnots); dyKnots = diag(yKnots); mainDiagDist = sum(sqrt(diff(dxKnots).^2 + diff(dyKnots).^2 + diff(zKnotsMainDiag).^2));
  sdxKnots = xKnots(M:M-1:end-1)'; sdyKnots = yKnots(M:M-1:end-1)'; skewDiagDist = sum(sqrt(diff(sdxKnots).^2 + diff(sdyKnots).^2 + diff(zKnotsSkewDiag).^2));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mappedMaxPositions = alignMappedSurfaces(VZminmesh,VZmaxmesh,mappedMinPositions,mappedMaxPositions,validXborders,validYborders,conformalJump,patchSize)
if nargin < 8
  patchSize = 21;
  if nargin < 7
    conformalJump = 1;
  end
end
patchSize = ceil(patchSize/conformalJump);
% pad the surfaces by one pixel so that the size remains the same after the difference operation
VZminmesh = [[VZminmesh 10*max(VZminmesh(:))*ones(size(VZminmesh,1),1)]; 10*max(VZminmesh(:))*ones(1,size(VZminmesh,2)+1)];
VZmaxmesh = [[VZmaxmesh 10*max(VZmaxmesh(:))*ones(size(VZmaxmesh,1),1)]; 10*max(VZmaxmesh(:))*ones(1,size(VZmaxmesh,2)+1)];
% calculate the absolute differences in xy between neighboring pixels
tmp1 = diff(VZminmesh,1,1); tmp1 = tmp1(:,1:end-1); tmp2 = diff(VZminmesh,1,2); tmp2 = tmp2(1:end-1,:); dMinSurface = abs(tmp1+i*tmp2);
tmp1 = diff(VZmaxmesh,1,1); tmp1 = tmp1(:,1:end-1); tmp2 = diff(VZmaxmesh,1,2); tmp2 = tmp2(1:end-1,:); dMaxSurface = abs(tmp1+i*tmp2);
% retain the region of interest, with a resolution specified by conformalJump
dMinSurface = dMinSurface(validXborders(1):conformalJump:validXborders(2), validYborders(1):conformalJump:validYborders(2));
dMaxSurface = dMaxSurface(validXborders(1):conformalJump:validXborders(2), validYborders(1):conformalJump:validYborders(2));
% calculate the cost as the sum of absolute slopes on both surfaces
patchCosts = conv2(dMinSurface+dMaxSurface, ones(patchSize),'valid');
% find the minimum cost
[row,col] = find(patchCosts == min(min(patchCosts)),1);
row = row+(patchSize-1)/2; col = col+(patchSize-1)/2;
% calculate and apply the corresponding shift
linearInd = sub2ind(size(dMinSurface),row,col);
shift1 = mappedMaxPositions(linearInd,1)-mappedMinPositions(linearInd,1);
mappedMaxPositions(:,1) = mappedMaxPositions(:,1) - shift1;
shift2 = mappedMaxPositions(linearInd,2)-mappedMinPositions(linearInd,2);
mappedMaxPositions(:,2) = mappedMaxPositions(:,2) - shift2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mappedPositions = conformalMap_indepFixedDiagonals(mainDiagDist,skewDiagDist,xpos,ypos,VZmesh)
% implements quasi-conformal mapping suggested in
% Levy et al., 'Least squares conformal maps for automatic texture atlas generation', 2002, ACM Transactions on Graphics
M = size(VZmesh,1); N = size(VZmesh,2);
col1 = kron([1;1],[1:M-1]');
temp1 = kron([1;M+1],ones(M-1,1));
temp2 = kron([M+1;M],ones(M-1,1));
oneColumn = [col1 col1+temp1 col1+temp2];
% every pixel is divided into 2 triangles
triangleCount = (2*M-2)*(N-1);
vertexCount = M*N;
triangulation = zeros(triangleCount, 3);
% store the positions of the vertices for each triangle - triangles are oriented consistently
for kk = 1:N-1
  triangulation((kk-1)*(2*M-2)+1:kk*(2*M-2),:) = oneColumn + (kk-1)*M;
end
Mreal = sparse([],[],[],triangleCount,vertexCount,triangleCount*3);
Mimag = sparse([],[],[],triangleCount,vertexCount,triangleCount*3);
% calculate the conformality condition (Riemann's theorem)
for triangle = 1:triangleCount
  for vertex = 1:3
    nodeNumber = triangulation(triangle,vertex);
    xind = rem(nodeNumber-1,M)+1;
    yind = floor((nodeNumber-1)/M)+1;
    trianglePos(vertex,:) = [xpos(xind) ypos(yind) VZmesh(xind,yind)];
  end
  [w1,w2,w3,zeta] = assignLocalCoordinates(trianglePos);
  denominator = sqrt(zeta/2);
  Mreal(triangle,triangulation(triangle,1)) = real(w1)/denominator;
  Mreal(triangle,triangulation(triangle,2)) = real(w2)/denominator;
  Mreal(triangle,triangulation(triangle,3)) = real(w3)/denominator;
  Mimag(triangle,triangulation(triangle,1)) = imag(w1)/denominator;
  Mimag(triangle,triangulation(triangle,2)) = imag(w2)/denominator;
  Mimag(triangle,triangulation(triangle,3)) = imag(w3)/denominator;
end
% minimize the LS error due to conformality condition of mapping triangles into triangles
% take the two fixed points required to solve the system as the corners of the main diagonal
mainDiagXdist = mainDiagDist*M/sqrt(M^2+N^2); mainDiagYdist = mainDiagXdist*N/M;
A = [Mreal(:,2:end-1) -Mimag(:,2:end-1); Mimag(:,2:end-1) Mreal(:,2:end-1)];
b = -[Mreal(:,[1 end]) -Mimag(:,[1 end]); Mimag(:,[1 end]) Mreal(:,[1 end])]*[[xpos(1);xpos(1)+mainDiagXdist];[ypos(1);ypos(1)+mainDiagYdist]];
mappedPositions1 = A\b;
mappedPositions1 = [[xpos(1);mappedPositions1(1:end/2);xpos(1)+mainDiagXdist] [ypos(1);mappedPositions1(1+end/2:end);ypos(1)+mainDiagYdist]];
% take the two fixed points required to solve the system as the corners of the skew diagonal
skewDiagXdist = skewDiagDist*M/sqrt(M^2+N^2); skewDiagYdist = skewDiagXdist*N/M; freeVar = [[1:M-1] [M+1:M*N-M] [M*N-M+2:M*N]];
A = [Mreal(:,freeVar) -Mimag(:,freeVar); Mimag(:,freeVar) Mreal(:,freeVar)];
b = -[Mreal(:,[M M*N-M+1]) -Mimag(:,[M M*N-M+1]); Mimag(:,[M M*N-M+1]) Mreal(:,[M M*N-M+1])]*[[xpos(1)+skewDiagXdist;xpos(1)];[ypos(1);ypos(1)+skewDiagYdist]];
mappedPositions2 = A\b;
mappedPositions2 = [[mappedPositions2(1:M-1);xpos(1)+skewDiagXdist;mappedPositions2(M:M*N-M-1);xpos(1);mappedPositions2(M*N-M:end/2)] ...
                    [mappedPositions2(1+end/2:M-1+end/2);ypos(1);mappedPositions2(end/2+M:end/2+M*N-M-1);ypos(1)+skewDiagYdist;mappedPositions2(end/2+M*N-M:end)]];
% take the mean of the two independent solutions and return it as the solution
mappedPositions = (mappedPositions1+mappedPositions2)/2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [w1,w2,w3,zeta] = assignLocalCoordinates(triangle)
% triangle is a 3x3 matrix where the rows represent the x,y,z coordinates of the vertices.
% The local triangle is defined on a plane, where the first vertex is at the origin(0,0) and the second vertex is at (0,-d12).
d12 = norm(triangle(1,:)-triangle(2,:));
d13 = norm(triangle(1,:)-triangle(3,:));
d23 = norm(triangle(2,:)-triangle(3,:));
y3 = ((-d12)^2+d13^2-d23^2)/(2*(-d12));
x3 = sqrt(d13^2-y3^2); % provisional

w2 = -x3-i*y3; w1 = x3+i*(y3-(-d12));
zeta = i*(conj(w2)*w1-conj(w1)*w2); % orientation indicator
w3 = i*(-d12);
zeta = abs(real(zeta));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function warpedVoxels = calcWarpedVoxels(vol,surfaceMapping,voxelDim,conformalJump)
% voxelDim: physical size of voxels in um, 1x3

mappedMinPositions=surfaceMapping.mappedMinPositions; mappedMaxPositions=surfaceMapping.mappedMaxPositions;
thisVZminmesh=surfaceMapping.thisVZminmesh; thisVZmaxmesh=surfaceMapping.thisVZmaxmesh; thisx=surfaceMapping.thisx; thisy=surfaceMapping.thisy;
% find voxels to be warped - only the voxels for which SAC surface annotations are available are considered
vol(1:surfaceMapping.thisx(1)-1,:,:)=0; vol(surfaceMapping.thisx(end)+1:end,:,:)=0;
vol(:,1:surfaceMapping.thisy(1)-1,:)=0; vol(:,surfaceMapping.thisy(end)+1:end,:)=0;
[xx, yy, zz] = ind2sub(size(vol), find(vol>0));
voxels = [xx, yy, zz];
% find 6-neighborhood voxels that are also in the list for each voxel
neighborList=cell(size(voxels,1),1);
[lia,locb] = ismember([xx+1 yy zz], voxels,'rows');
[lia,tmp]  = ismember([xx-1 yy zz], voxels,'rows'); locb = [locb tmp];
[lia,tmp]  = ismember([xx yy+1 zz], voxels,'rows'); locb = [locb tmp];
[lia,tmp]  = ismember([xx yy-1 zz], voxels,'rows'); locb = [locb tmp];
[lia,tmp]  = ismember([xx yy zz+1], voxels,'rows'); locb = [locb tmp];
[lia,tmp]  = ismember([xx yy zz-1], voxels,'rows'); locb = [locb tmp];
for kk = 1:size(voxels,1)
  tmp = locb(kk,:);
  neighborList{kk} = tmp(tmp~=0);
end
% generate correspondence points for the points on the surfaces
[tmpymesh,tmpxmesh] = meshgrid([thisy(1):conformalJump:thisy(end)],[thisx(1):conformalJump:thisx(end)]);
tmpminmesh = thisVZminmesh(thisx(1):conformalJump:thisx(end),thisy(1):conformalJump:thisy(end));
tmpmaxmesh = thisVZmaxmesh(thisx(1):conformalJump:thisx(end),thisy(1):conformalJump:thisy(end));
topInputPos = [tmpxmesh(:) tmpymesh(:) tmpminmesh(:)]; botInputPos = [tmpxmesh(:) tmpymesh(:) tmpmaxmesh(:)];
topOutputPos = [mappedMinPositions(:,1) mappedMinPositions(:,2) median(tmpminmesh(:))*ones(size(mappedMinPositions,1),1)];
botOutputPos = [mappedMaxPositions(:,1) mappedMaxPositions(:,2) median(tmpmaxmesh(:))*ones(size(mappedMaxPositions,1),1)];
% use the correspondence points to calculate local transforms and use those local transforms to map points on the arbor
voxels = localLSregistration(voxels,topInputPos,botInputPos,topOutputPos,botOutputPos,conformalJump);
% switch to physical dimensions (in um)
voxels(:,1) = voxels(:,1)*voxelDim(1); voxels(:,2) = voxels(:,2)*voxelDim(2); voxels(:,3) = voxels(:,3)*voxelDim(3);
% calculate median band positions in z
medVZminmesh = median(tmpminmesh(:)); medVZmaxmesh = median(tmpmaxmesh(:));
% return the warped voxels and the corresponding median SAC surface values
warpedVoxels.voxels=voxels; warpedArbor.medVZmin=medVZminmesh; warpedArbor.medVZmax=medVZmaxmesh;
warpedVoxels.neighborList=neighborList;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function nodes = localLSregistration(nodes,topInputPos,botInputPos,topOutputPos,botOutputPos,conformalJump)
% aX^2+bXY+cY^2+dX+eY+f+gZX^2+hXYZ+iZY^2+jXZ+kYZ+lZ -> at least 12 equations needed
maxOrder=2; % maximum multinomial order in xy
for kk = 1:size(nodes,1)
  window=conformalJump; % neighborhood extent for the LS registration
  % gradually increase 'window' to avoid an underdetermined system
  while(true)
    % fetch the band points around an xy neighborhood for each point on the arbor
    xpos = nodes(kk,1); ypos = nodes(kk,2); zpos = nodes(kk,3);
    lx = round(xpos-window); ux = round(xpos+window); ly = round(ypos-window); uy = round(ypos+window);
    thisInT = topInputPos(topInputPos(:,1)>=lx & topInputPos(:,1)<=ux & topInputPos(:,2)>=ly & topInputPos(:,2)<=uy,:);
    thisInB = botInputPos(botInputPos(:,1)>=lx & botInputPos(:,1)<=ux & botInputPos(:,2)>=ly & botInputPos(:,2)<=uy,:);
    thisIn = [thisInT; thisInB];
    thisOutT = topOutputPos(topInputPos(:,1)>=lx & topInputPos(:,1)<=ux & topInputPos(:,2)>=ly & topInputPos(:,2)<=uy,:);
    thisOutB = botOutputPos(botInputPos(:,1)>=lx & botInputPos(:,1)<=ux & botInputPos(:,2)>=ly & botInputPos(:,2)<=uy,:);
    thisOut = [thisOutT; thisOutB];
    % convert band correspondence data into local coordinates
    xShift = mean(thisIn(:,1)); yShift = mean(thisIn(:,2));
    thisIn(:,1) = thisIn(:,1)-xShift; thisOut(:,1) = thisOut(:,1)-xShift;
    thisIn(:,2) = thisIn(:,2)-yShift; thisOut(:,2) = thisOut(:,2)-yShift;
    % calculate the transformation that maps the band points to their correspondences
    quadData = [thisIn(:,1:2) ones(size(thisIn,1),1)];
    for totalOrd = 2:maxOrder; for ord = 0:totalOrd; % slightly more general - it can handle higher lateral polynomial orders
      quadData = [(thisIn(:,1).^ord).*(thisIn(:,2).^(totalOrd-ord)) quadData];
    end; end;
    quadData = [quadData kron(thisIn(:,3),ones(1,size(quadData,2))).*quadData];
    if rank(quadData)<12
      window=window+1;
    else
      break;
    end
  end
  transformMat = lscov(quadData,thisOut);
  shiftedNode = [xpos-xShift ypos-yShift];
  quadData = [shiftedNode(1:2) 1];
  for totalOrd = 2:maxOrder; for ord = 0:totalOrd; % slightly more general - it can handle higher lateral polynomial orders
    quadData = [(shiftedNode(1).^ord).*(shiftedNode(2).^(totalOrd-ord)) quadData];
  end; end;
  quadData = [quadData kron(zpos,ones(1,size(quadData,2))).*quadData];
  % transform the arbor points using the calculated transform
  nodes(kk,:) = quadData*transformMat; nodes(kk,1) = nodes(kk,1) + xShift; nodes(kk,2) = nodes(kk,2) + yShift;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function interpolated = pureGridder1d(zSamples,density,n)

% data must be in [-0.5, 0.5]
alpha=2; W=5; error=1e-3; S=ceil(0.91/error/alpha); beta=pi*sqrt((W/alpha*(alpha-1/2))^2-0.8);
% generate interpolating low-pass filter
Gz=alpha*n; F_kbZ=besseli(0,beta*sqrt(1-([-1:2/(S*W):1]).^2)); z=-(alpha*n/2):(alpha*n/2)-1; %F_kbZ=(Gz/W)*besseli(0,beta*sqrt(1-([-1:2/(S*W):1]).^2));
F_kbZ=F_kbZ/max(F_kbZ(:));
% generate Fourier transform of 1d interpolating kernels
kbZ=sqrt(alpha*n)*sin(sqrt((pi*W*z/Gz).^2-beta^2))./sqrt((pi*W*z/Gz).^2-beta^2);
% zero out output array in the alphaX grid - use a vector representation to be able to use sparse matrix structure
n = alpha*n; interpolated = zeros(n,1);
% convert samples to matrix indices
nz = (n/2+1) + n*zSamples;
% loop over samples in kernel
for lz = -(W-1)/2:(W-1)/2,
      % find nearest samples
      nzt = round(nz+lz);
      % compute weighting for KB kernel using linear interpolation
      zpos=S*((nz-nzt)-(-W/2))+1; kwz = F_kbZ(round(zpos))';
      % map samples outside the matrix to the edges
      nzt = max(nzt,1); nzt = min(nzt,n);
      % use sparse matrix to turn k-space trajectory into 2D matrix
      interpolated = interpolated+sparse(nzt,1,density.*kwz,n,1);
end;
interpolated = full(interpolated);
% zero out edge samples, since these may be due to samples outside the matrix
interpolated(1) = 0; interpolated(n) = 0;
n = n/alpha;
interpolated = myifft(interpolated,n);
% generate Fourier domain deapodization function and deapodize
deapod = kbZ(n/2+1:3*n/2)'; interpolated = interpolated./deapod;
% return to spatial domain
interpolated = abs(myfft3(interpolated));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function f=myifft(F,u)
% does the centering(shifts) and normalization
%needs a slight modification to actually support rectangular images
if nargin<2
f=ifftshift(ifft(ifftshift(F)))*sqrt(numel(F));
else
f=ifftshift(ifft(ifftshift(F)))*sqrt(u);
zoffset=ceil((size(f,1)-u)/2);
f=f(zoffset+1:zoffset+u);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function F=myfft3(f,u,v,w)
% does the centering(shifts) and normalization
%needs a slight modification to actually support rectangular images
if nargin<4
F=fftshift(fftn(fftshift(f)))/sqrt(prod(size(f)));
else
F=zeros(u,v,w);
zoffset=(u-size(f,1))/2; xoffset=(v-size(f,2))/2; yoffset=(w-size(f,3))/2;
F(zoffset+1:zoffset+size(f,1),xoffset+1:xoffset+size(f,2),yoffset+1:yoffset+size(f,3))=f;
F=fftshift(fftn(fftshift(F)))/sqrt(prod(size(f)));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [zgrid,xgrid,ygrid] = gridfit(x,y,z,xnodes,ynodes,varargin)
%--------------------------%
%Copyright (c) 2006, John D'Errico
%All rights reserved.

%Redistribution and use in source and binary forms, with or without
%modification, are permitted provided that the following conditions are
%met:

%    * Redistributions of source code must retain the above copyright
%      notice, this list of conditions and the following disclaimer.
%    * Redistributions in binary form must reproduce the above copyright
%      notice, this list of conditions and the following disclaimer in
%      the documentation and/or other materials provided with the distribution

%THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
%LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
%CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
%SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
%CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%POSSIBILITY OF SUCH DAMAGE.
%--------------------------%

% gridfit: estimates a surface on a 2d grid, based on scattered data
%          Replicates are allowed. All methods extrapolate to the grid
%          boundaries. Gridfit uses a modified ridge estimator to
%          generate the surface, where the bias is toward smoothness.
%
%          Gridfit is not an interpolant. Its goal is a smooth surface
%          that approximates your data, but allows you to control the
%          amount of smoothing.
%
% usage #1: zgrid = gridfit(x,y,z,xnodes,ynodes);
% usage #2: [zgrid,xgrid,ygrid] = gridfit(x,y,z,xnodes,ynodes);
% usage #3: zgrid = gridfit(x,y,z,xnodes,ynodes,prop,val,prop,val,...);
%
% Arguments: (input)
%  x,y,z - vectors of equal lengths, containing arbitrary scattered data
%          The only constraint on x and y is they cannot ALL fall on a
%          single line in the x-y plane. Replicate points will be treated
%          in a least squares sense.
%
%          ANY points containing a NaN are ignored in the estimation
%
%  xnodes - vector defining the nodes in the grid in the independent
%          variable (x). xnodes need not be equally spaced. xnodes
%          must completely span the data. If they do not, then the
%          'extend' property is applied, adjusting the first and last
%          nodes to be extended as necessary. See below for a complete
%          description of the 'extend' property.
%
%          If xnodes is a scalar integer, then it specifies the number
%          of equally spaced nodes between the min and max of the data.
%
%  ynodes - vector defining the nodes in the grid in the independent
%          variable (y). ynodes need not be equally spaced.
%
%          If ynodes is a scalar integer, then it specifies the number
%          of equally spaced nodes between the min and max of the data.
%
%          Also see the extend property.
%
%  Additional arguments follow in the form of property/value pairs.
%  Valid properties are:
%    'smoothness', 'interp', 'regularizer', 'solver', 'maxiter'
%    'extend', 'tilesize', 'overlap'
%
%  Any UNAMBIGUOUS shortening (even down to a single letter) is
%  valid for property names. All properties have default values,
%  chosen (I hope) to give a reasonable result out of the box.
%
%   'smoothness' - scalar or vector of length 2 - determines the
%          eventual smoothness of the estimated surface. A larger
%          value here means the surface will be smoother. Smoothness
%          must be a non-negative real number.
%
%          If this parameter is a vector of length 2, then it defines
%          the relative smoothing to be associated with the x and y
%          variables. This allows the user to apply a different amount
%          of smoothing in the x dimension compared to the y dimension.
%
%          Note: the problem is normalized in advance so that a
%          smoothness of 1 MAY generate reasonable results. If you
%          find the result is too smooth, then use a smaller value
%          for this parameter. Likewise, bumpy surfaces suggest use
%          of a larger value. (Sometimes, use of an iterative solver
%          with too small a limit on the maximum number of iterations
%          will result in non-convergence.)
%
%          DEFAULT: 1
%
%
%   'interp' - character, denotes the interpolation scheme used
%          to interpolate the data.
%
%          DEFAULT: 'triangle'
%
%          'bilinear' - use bilinear interpolation within the grid
%                     (also known as tensor product linear interpolation)
%
%          'triangle' - split each cell in the grid into a triangle,
%                     then linear interpolation inside each triangle
%
%          'nearest' - nearest neighbor interpolation. This will
%                     rarely be a good choice, but I included it
%                     as an option for completeness.
%
%
%   'regularizer' - character flag, denotes the regularization
%          paradignm to be used. There are currently three options.
%
%          DEFAULT: 'gradient'
%
%          'diffusion' or 'laplacian' - uses a finite difference
%              approximation to the Laplacian operator (i.e, del^2).
%
%              We can think of the surface as a plate, wherein the
%              bending rigidity of the plate is specified by the user
%              as a number relative to the importance of fidelity to
%              the data. A stiffer plate will result in a smoother
%              surface overall, but fit the data less well. I've
%              modeled a simple plate using the Laplacian, del^2. (A
%              projected enhancement is to do a better job with the
%              plate equations.)
%
%              We can also view the regularizer as a diffusion problem,
%              where the relative thermal conductivity is supplied.
%              Here interpolation is seen as a problem of finding the
%              steady temperature profile in an object, given a set of
%              points held at a fixed temperature. Extrapolation will
%              be linear. Both paradigms are appropriate for a Laplacian
%              regularizer.
%
%          'gradient' - attempts to ensure the gradient is as smooth
%              as possible everywhere. Its subtly different from the
%              'diffusion' option, in that here the directional
%              derivatives are biased to be smooth across cell
%              boundaries in the grid.
%
%              The gradient option uncouples the terms in the Laplacian.
%              Think of it as two coupled PDEs instead of one PDE. Why
%              are they different at all? The terms in the Laplacian
%              can balance each other.
%
%          'springs' - uses a spring model connecting nodes to each
%              other, as well as connecting data points to the nodes
%              in the grid. This choice will cause any extrapolation
%              to be as constant as possible.
%
%              Here the smoothing parameter is the relative stiffness
%              of the springs connecting the nodes to each other compared
%              to the stiffness of a spting connecting the lattice to
%              each data point. Since all springs have a rest length
%              (length at which the spring has zero potential energy)
%              of zero, any extrapolation will be minimized.
%
%          Note: The 'springs' regularizer tends to drag the surface
%          towards the mean of all the data, so too large a smoothing
%          parameter may be a problem.
%
%
%   'solver' - character flag - denotes the solver used for the
%          resulting linear system. Different solvers will have
%          different solution times depending upon the specific
%          problem to be solved. Up to a certain size grid, the
%          direct \ solver will often be speedy, until memory
%          swaps causes problems.
%
%          What solver should you use? Problems with a significant
%          amount of extrapolation should avoid lsqr. \ may be
%          best numerically for small smoothnesss parameters and
%          high extents of extrapolation.
%
%          Large numbers of points will slow down the direct
%          \, but when applied to the normal equations, \ can be
%          quite fast. Since the equations generated by these
%          methods will tend to be well conditioned, the normal
%          equations are not a bad choice of method to use. Beware
%          when a small smoothing parameter is used, since this will
%          make the equations less well conditioned.
%
%          DEFAULT: 'normal'
%
%          '\' - uses matlab's backslash operator to solve the sparse
%                     system. 'backslash' is an alternate name.
%
%          'symmlq' - uses matlab's iterative symmlq solver
%
%          'lsqr' - uses matlab's iterative lsqr solver
%
%          'normal' - uses \ to solve the normal equations.
%
%
%   'maxiter' - only applies to iterative solvers - defines the
%          maximum number of iterations for an iterative solver
%
%          DEFAULT: min(10000,length(xnodes)*length(ynodes))
%
%
%   'extend' - character flag - controls whether the first and last
%          nodes in each dimension are allowed to be adjusted to
%          bound the data, and whether the user will be warned if
%          this was deemed necessary to happen.
%
%          DEFAULT: 'warning'
%
%          'warning' - Adjust the first and/or last node in
%                     x or y if the nodes do not FULLY contain
%                     the data. Issue a warning message to this
%                     effect, telling the amount of adjustment
%                     applied.
%
%          'never'  - Issue an error message when the nodes do
%                     not absolutely contain the data.
%
%          'always' - automatically adjust the first and last
%                     nodes in each dimension if necessary.
%                     No warning is given when this option is set.
%
%
%   'tilesize' - grids which are simply too large to solve for
%          in one single estimation step can be built as a set
%          of tiles. For example, a 1000x1000 grid will require
%          the estimation of 1e6 unknowns. This is likely to
%          require more memory (and time) than you have available.
%          But if your data is dense enough, then you can model
%          it locally using smaller tiles of the grid.
%
%          My recommendation for a reasonable tilesize is
%          roughly 100 to 200. Tiles of this size take only
%          a few seconds to solve normally, so the entire grid
%          can be modeled in a finite amount of time. The minimum
%          tilesize can never be less than 3, although even this
%          size tile is so small as to be ridiculous.
%
%          If your data is so sparse than some tiles contain
%          insufficient data to model, then those tiles will
%          be left as NaNs.
%
%          DEFAULT: inf
%
%
%   'overlap' - Tiles in a grid have some overlap, so they
%          can minimize any problems along the edge of a tile.
%          In this overlapped region, the grid is built using a
%          bi-linear combination of the overlapping tiles.
%
%          The overlap is specified as a fraction of the tile
%          size, so an overlap of 0.20 means there will be a 20%
%          overlap of successive tiles. I do allow a zero overlap,
%          but it must be no more than 1/2.
%
%          0 <= overlap <= 0.5
%
%          Overlap is ignored if the tilesize is greater than the
%          number of nodes in both directions.
%
%          DEFAULT: 0.20
%
%
%   'autoscale' - Some data may have widely different scales on
%          the respective x and y axes. If this happens, then
%          the regularization may experience difficulties. 
%          
%          autoscale = 'on' will cause gridfit to scale the x
%          and y node intervals to a unit length. This should
%          improve the regularization procedure. The scaling is
%          purely internal. 
%
%          autoscale = 'off' will disable automatic scaling
%
%          DEFAULT: 'on'
%
%
% Arguments: (output)
%  zgrid   - (nx,ny) array containing the fitted surface
%
%  xgrid, ygrid - as returned by meshgrid(xnodes,ynodes)
%
%
% Speed considerations:
%  Remember that gridfit must solve a LARGE system of linear
%  equations. There will be as many unknowns as the total
%  number of nodes in the final lattice. While these equations
%  may be sparse, solving a system of 10000 equations may take
%  a second or so. Very large problems may benefit from the
%  iterative solvers or from tiling.
%
%
% Example usage:
%
%  x = rand(100,1);
%  y = rand(100,1);
%  z = exp(x+2*y);
%  xnodes = 0:.1:1;
%  ynodes = 0:.1:1;
%
%  g = gridfit(x,y,z,xnodes,ynodes);
%
% Note: this is equivalent to the following call:
%
%  g = gridfit(x,y,z,xnodes,ynodes, ...
%              'smooth',1, ...
%              'interp','triangle', ...
%              'solver','normal', ...
%              'regularizer','gradient', ...
%              'extend','warning', ...
%              'tilesize',inf);
%
%
% Author: John D'Errico
% e-mail address: woodchips@rochester.rr.com
% Release: 2.0
% Release date: 5/23/06

% set defaults
params.smoothness = 1;
params.interp = 'triangle';
params.regularizer = 'gradient';
params.solver = 'backslash';
params.maxiter = [];
params.extend = 'warning';
params.tilesize = inf;
params.overlap = 0.20;
params.mask = []; 
params.autoscale = 'on';
params.xscale = 1;
params.yscale = 1;

% was the params struct supplied?
if ~isempty(varargin)
  if isstruct(varargin{1})
    % params is only supplied if its a call from tiled_gridfit
    params = varargin{1};
    if length(varargin)>1
      % check for any overrides
      params = parse_pv_pairs(params,varargin{2:end});
    end
  else
    % check for any overrides of the defaults
    params = parse_pv_pairs(params,varargin);

  end
end

% check the parameters for acceptability
params = check_params(params);

% ensure all of x,y,z,xnodes,ynodes are column vectors,
% also drop any NaN data
x=x(:);
y=y(:);
z=z(:);
k = isnan(x) | isnan(y) | isnan(z);
if any(k)
  x(k)=[];
  y(k)=[];
  z(k)=[];
end
xmin = min(x);
xmax = max(x);
ymin = min(y);
ymax = max(y);

% did they supply a scalar for the nodes?
if length(xnodes)==1
  xnodes = linspace(xmin,xmax,xnodes)';
  xnodes(end) = xmax; % make sure it hits the max
end
if length(ynodes)==1
  ynodes = linspace(ymin,ymax,ynodes)';
  ynodes(end) = ymax; % make sure it hits the max
end

xnodes=xnodes(:);
ynodes=ynodes(:);
dx = diff(xnodes);
dy = diff(ynodes);
nx = length(xnodes);
ny = length(ynodes);
ngrid = nx*ny;

% set the scaling if autoscale was on
if strcmpi(params.autoscale,'on')
  params.xscale = mean(dx);
  params.yscale = mean(dy);
  params.autoscale = 'off';
end

% check to see if any tiling is necessary
if (params.tilesize < max(nx,ny))
  % split it into smaller tiles. compute zgrid and ygrid
  % at the very end if requested
  zgrid = tiled_gridfit(x,y,z,xnodes,ynodes,params);
else
  % its a single tile.
  
  % mask must be either an empty array, or a boolean
  % aray of the same size as the final grid.
  nmask = size(params.mask);
  if ~isempty(params.mask) && ((nmask(2)~=nx) || (nmask(1)~=ny))
    if ((nmask(2)==ny) || (nmask(1)==nx))
      error 'Mask array is probably transposed from proper orientation.'
    else
      error 'Mask array must be the same size as the final grid.'
    end
  end
  if ~isempty(params.mask)
    params.maskflag = 1;
  else
    params.maskflag = 0;
  end

  % default for maxiter?
  if isempty(params.maxiter)
    params.maxiter = min(10000,nx*ny);
  end

  % check lengths of the data
  n = length(x);
  if (length(y)~=n) || (length(z)~=n)
    error 'Data vectors are incompatible in size.'
  end
  if n<3
    error 'Insufficient data for surface estimation.'
  end

  % verify the nodes are distinct
  if any(diff(xnodes)<=0) || any(diff(ynodes)<=0)
    error 'xnodes and ynodes must be monotone increasing'
  end

  % do we need to tweak the first or last node in x or y?
  if xmin<xnodes(1)
    switch params.extend
      case 'always'
        xnodes(1) = xmin;
      case 'warning'
        warning('GRIDFIT:extend',['xnodes(1) was decreased by: ',num2str(xnodes(1)-xmin),', new node = ',num2str(xmin)])
        xnodes(1) = xmin;
      case 'never'
        error(['Some x (',num2str(xmin),') falls below xnodes(1) by: ',num2str(xnodes(1)-xmin)])
    end
  end
  if xmax>xnodes(end)
    switch params.extend
      case 'always'
        xnodes(end) = xmax;
      case 'warning'
        warning('GRIDFIT:extend',['xnodes(end) was increased by: ',num2str(xmax-xnodes(end)),', new node = ',num2str(xmax)])
        xnodes(end) = xmax;
      case 'never'
        error(['Some x (',num2str(xmax),') falls above xnodes(end) by: ',num2str(xmax-xnodes(end))])
    end
  end
  if ymin<ynodes(1)
    switch params.extend
      case 'always'
        ynodes(1) = ymin;
      case 'warning'
        warning('GRIDFIT:extend',['ynodes(1) was decreased by: ',num2str(ynodes(1)-ymin),', new node = ',num2str(ymin)])
        ynodes(1) = ymin;
      case 'never'
        error(['Some y (',num2str(ymin),') falls below ynodes(1) by: ',num2str(ynodes(1)-ymin)])
    end
  end
  if ymax>ynodes(end)
    switch params.extend
      case 'always'
        ynodes(end) = ymax;
      case 'warning'
        warning('GRIDFIT:extend',['ynodes(end) was increased by: ',num2str(ymax-ynodes(end)),', new node = ',num2str(ymax)])
        ynodes(end) = ymax;
      case 'never'
        error(['Some y (',num2str(ymax),') falls above ynodes(end) by: ',num2str(ymax-ynodes(end))])
    end
  end
  
  % determine which cell in the array each point lies in
  [junk,indx] = histc(x,xnodes); %#ok
  [junk,indy] = histc(y,ynodes); %#ok
  % any point falling at the last node is taken to be
  % inside the last cell in x or y.
  k=(indx==nx);
  indx(k)=indx(k)-1;
  k=(indy==ny);
  indy(k)=indy(k)-1;
  ind = indy + ny*(indx-1);
  
  % Do we have a mask to apply?
  if params.maskflag
    % if we do, then we need to ensure that every
    % cell with at least one data point also has at
    % least all of its corners unmasked.
    params.mask(ind) = 1;
    params.mask(ind+1) = 1;
    params.mask(ind+ny) = 1;
    params.mask(ind+ny+1) = 1;
  end
  
  % interpolation equations for each point
  tx = min(1,max(0,(x - xnodes(indx))./dx(indx)));
  ty = min(1,max(0,(y - ynodes(indy))./dy(indy)));
  % Future enhancement: add cubic interpolant
  switch params.interp
    case 'triangle'
      % linear interpolation inside each triangle
      k = (tx > ty);
      L = ones(n,1);
      L(k) = ny;
      
      t1 = min(tx,ty);
      t2 = max(tx,ty);
      A = sparse(repmat((1:n)',1,3),[ind,ind+ny+1,ind+L], ...
        [1-t2,t1,t2-t1],n,ngrid);
      
    case 'nearest'
      % nearest neighbor interpolation in a cell
      k = round(1-ty) + round(1-tx)*ny;
      A = sparse((1:n)',ind+k,ones(n,1),n,ngrid);
      
    case 'bilinear'
      % bilinear interpolation in a cell
      A = sparse(repmat((1:n)',1,4),[ind,ind+1,ind+ny,ind+ny+1], ...
        [(1-tx).*(1-ty), (1-tx).*ty, tx.*(1-ty), tx.*ty], ...
        n,ngrid);
      
  end
  rhs = z;
  
  % do we have relative smoothing parameters?
  if numel(params.smoothness) == 1
    % it was scalar, so treat both dimensions equally
    smoothparam = params.smoothness;
    xyRelativeStiffness = [1;1];
  else
    % It was a vector, so anisotropy reigns.
    % I've already checked that the vector was of length 2
    smoothparam = sqrt(prod(params.smoothness));
    xyRelativeStiffness = params.smoothness(:)./smoothparam;
  end
  
  % Build regularizer. Add del^4 regularizer one day.
  switch params.regularizer
    case 'springs'
      % zero "rest length" springs
      [i,j] = meshgrid(1:nx,1:(ny-1));
      ind = j(:) + ny*(i(:)-1);
      m = nx*(ny-1);
      stiffness = 1./(dy/params.yscale);
      Areg = sparse(repmat((1:m)',1,2),[ind,ind+1], ...
        xyRelativeStiffness(2)*stiffness(j(:))*[-1 1], ...
        m,ngrid);
      
      [i,j] = meshgrid(1:(nx-1),1:ny);
      ind = j(:) + ny*(i(:)-1);
      m = (nx-1)*ny;
      stiffness = 1./(dx/params.xscale);
      Areg = [Areg;sparse(repmat((1:m)',1,2),[ind,ind+ny], ...
        xyRelativeStiffness(1)*stiffness(i(:))*[-1 1],m,ngrid)];
      
      [i,j] = meshgrid(1:(nx-1),1:(ny-1));
      ind = j(:) + ny*(i(:)-1);
      m = (nx-1)*(ny-1);
      stiffness = 1./sqrt((dx(i(:))/params.xscale/xyRelativeStiffness(1)).^2 + ...
        (dy(j(:))/params.yscale/xyRelativeStiffness(2)).^2);
      
      Areg = [Areg;sparse(repmat((1:m)',1,2),[ind,ind+ny+1], ...
        stiffness*[-1 1],m,ngrid)];
      
      Areg = [Areg;sparse(repmat((1:m)',1,2),[ind+1,ind+ny], ...
        stiffness*[-1 1],m,ngrid)];
      
    case {'diffusion' 'laplacian'}
      % thermal diffusion using Laplacian (del^2)
      [i,j] = meshgrid(1:nx,2:(ny-1));
      ind = j(:) + ny*(i(:)-1);
      dy1 = dy(j(:)-1)/params.yscale;
      dy2 = dy(j(:))/params.yscale;
      
      Areg = sparse(repmat(ind,1,3),[ind-1,ind,ind+1], ...
        xyRelativeStiffness(2)*[-2./(dy1.*(dy1+dy2)), ...
        2./(dy1.*dy2), -2./(dy2.*(dy1+dy2))],ngrid,ngrid);
      
      [i,j] = meshgrid(2:(nx-1),1:ny);
      ind = j(:) + ny*(i(:)-1);
      dx1 = dx(i(:)-1)/params.xscale;
      dx2 = dx(i(:))/params.xscale;
      
      Areg = Areg + sparse(repmat(ind,1,3),[ind-ny,ind,ind+ny], ...
        xyRelativeStiffness(1)*[-2./(dx1.*(dx1+dx2)), ...
        2./(dx1.*dx2), -2./(dx2.*(dx1+dx2))],ngrid,ngrid);
      
    case 'gradient'
      % Subtly different from the Laplacian. A point for future
      % enhancement is to do it better for the triangle interpolation
      % case.
      [i,j] = meshgrid(1:nx,2:(ny-1));
      ind = j(:) + ny*(i(:)-1);
      dy1 = dy(j(:)-1)/params.yscale;
      dy2 = dy(j(:))/params.yscale;
      
      Areg = sparse(repmat(ind,1,3),[ind-1,ind,ind+1], ...
        xyRelativeStiffness(2)*[-2./(dy1.*(dy1+dy2)), ...
        2./(dy1.*dy2), -2./(dy2.*(dy1+dy2))],ngrid,ngrid);
      
      [i,j] = meshgrid(2:(nx-1),1:ny);
      ind = j(:) + ny*(i(:)-1);
      dx1 = dx(i(:)-1)/params.xscale;
      dx2 = dx(i(:))/params.xscale;
      
      Areg = [Areg;sparse(repmat(ind,1,3),[ind-ny,ind,ind+ny], ...
        xyRelativeStiffness(1)*[-2./(dx1.*(dx1+dx2)), ...
        2./(dx1.*dx2), -2./(dx2.*(dx1+dx2))],ngrid,ngrid)];
      
  end
  nreg = size(Areg,1);
  
  % Append the regularizer to the interpolation equations,
  % scaling the problem first. Use the 1-norm for speed.
  NA = norm(A,1);
  NR = norm(Areg,1);
  A = [A;Areg*(smoothparam*NA/NR)];
  rhs = [rhs;zeros(nreg,1)];
  % do we have a mask to apply?
  if params.maskflag
    unmasked = find(params.mask);
  end
  % solve the full system, with regularizer attached
  switch params.solver
    case {'\' 'backslash'}
      if params.maskflag
        % there is a mask to use
        zgrid=nan(ny,nx);
        zgrid(unmasked) = A(:,unmasked)\rhs;
      else
        % no mask
        zgrid = reshape(A\rhs,ny,nx);
      end
      
    case 'normal'
      % The normal equations, solved with \. Can be faster
      % for huge numbers of data points, but reasonably
      % sized grids. The regularizer makes A well conditioned
      % so the normal equations are not a terribly bad thing
      % here.
      if params.maskflag
        % there is a mask to use
        Aunmasked = A(:,unmasked);
        zgrid=nan(ny,nx);
        zgrid(unmasked) = (Aunmasked'*Aunmasked)\(Aunmasked'*rhs);
      else
        zgrid = reshape((A'*A)\(A'*rhs),ny,nx);
      end
      
    case 'symmlq'
      % iterative solver - symmlq - requires a symmetric matrix,
      % so use it to solve the normal equations. No preconditioner.
      tol = abs(max(z)-min(z))*1.e-13;
      if params.maskflag
        % there is a mask to use
        zgrid=nan(ny,nx);
        [zgrid(unmasked),flag] = symmlq(A(:,unmasked)'*A(:,unmasked), ...
          A(:,unmasked)'*rhs,tol,params.maxiter);
      else
        [zgrid,flag] = symmlq(A'*A,A'*rhs,tol,params.maxiter);
        zgrid = reshape(zgrid,ny,nx);
      end
      % display a warning if convergence problems
      switch flag
        case 0
          % no problems with convergence
        case 1
          % SYMMLQ iterated MAXIT times but did not converge.
          warning('GRIDFIT:solver',['Symmlq performed ',num2str(params.maxiter), ...
            ' iterations but did not converge.'])
        case 3
          % SYMMLQ stagnated, successive iterates were the same
          warning('GRIDFIT:solver','Symmlq stagnated without apparent convergence.')
        otherwise
          warning('GRIDFIT:solver',['One of the scalar quantities calculated in',...
            ' symmlq was too small or too large to continue computing.'])
      end
      
    case 'lsqr'
      % iterative solver - lsqr. No preconditioner here.
      tol = abs(max(z)-min(z))*1.e-13;
      if params.maskflag
        % there is a mask to use
        zgrid=nan(ny,nx);
        [zgrid(unmasked),flag] = lsqr(A(:,unmasked),rhs,tol,params.maxiter);
      else
        [zgrid,flag] = lsqr(A,rhs,tol,params.maxiter);
        zgrid = reshape(zgrid,ny,nx);
      end
      
      % display a warning if convergence problems
      switch flag
        case 0
          % no problems with convergence
        case 1
          % lsqr iterated MAXIT times but did not converge.
          warning('GRIDFIT:solver',['Lsqr performed ', ...
            num2str(params.maxiter),' iterations but did not converge.'])
        case 3
          % lsqr stagnated, successive iterates were the same
          warning('GRIDFIT:solver','Lsqr stagnated without apparent convergence.')
        case 4
          warning('GRIDFIT:solver',['One of the scalar quantities calculated in',...
            ' LSQR was too small or too large to continue computing.'])
      end
      
  end  % switch params.solver
  
end  % if params.tilesize...

% only generate xgrid and ygrid if requested.
if nargout>1
  [xgrid,ygrid]=meshgrid(xnodes,ynodes);
end

% ============================================
% End of main function - gridfit
% ============================================

% ============================================
% subfunction - parse_pv_pairs
% ============================================
function params=parse_pv_pairs(params,pv_pairs)
% parse_pv_pairs: parses sets of property value pairs, allows defaults
% usage: params=parse_pv_pairs(default_params,pv_pairs)
%
% arguments: (input)
%  default_params - structure, with one field for every potential
%             property/value pair. Each field will contain the default
%             value for that property. If no default is supplied for a
%             given property, then that field must be empty.
%
%  pv_array - cell array of property/value pairs.
%             Case is ignored when comparing properties to the list
%             of field names. Also, any unambiguous shortening of a
%             field/property name is allowed.
%
% arguments: (output)
%  params   - parameter struct that reflects any updated property/value
%             pairs in the pv_array.
%
% Example usage:
% First, set default values for the parameters. Assume we
% have four parameters that we wish to use optionally in
% the function examplefun.
%
%  - 'viscosity', which will have a default value of 1
%  - 'volume', which will default to 1
%  - 'pie' - which will have default value 3.141592653589793
%  - 'description' - a text field, left empty by default
%
% The first argument to examplefun is one which will always be
% supplied.
%
%   function examplefun(dummyarg1,varargin)
%   params.Viscosity = 1;
%   params.Volume = 1;
%   params.Pie = 3.141592653589793
%
%   params.Description = '';
%   params=parse_pv_pairs(params,varargin);
%   params
%
% Use examplefun, overriding the defaults for 'pie', 'viscosity'
% and 'description'. The 'volume' parameter is left at its default.
%
%   examplefun(rand(10),'vis',10,'pie',3,'Description','Hello world')
%
% params = 
%     Viscosity: 10
%        Volume: 1
%           Pie: 3
%   Description: 'Hello world'
%
% Note that capitalization was ignored, and the property 'viscosity'
% was truncated as supplied. Also note that the order the pairs were
% supplied was arbitrary.

npv = length(pv_pairs);
n = npv/2;

if n~=floor(n)
  error 'Property/value pairs must come in PAIRS.'
end
if n<=0
  % just return the defaults
  return
end

if ~isstruct(params)
  error 'No structure for defaults was supplied'
end

% there was at least one pv pair. process any supplied
propnames = fieldnames(params);
lpropnames = lower(propnames);
for i=1:n
  p_i = lower(pv_pairs{2*i-1});
  v_i = pv_pairs{2*i};
  
  ind = strmatch(p_i,lpropnames,'exact');
  if isempty(ind)
    ind = find(strncmp(p_i,lpropnames,length(p_i)));
    if isempty(ind)
      error(['No matching property found for: ',pv_pairs{2*i-1}])
    elseif length(ind)>1
      error(['Ambiguous property name: ',pv_pairs{2*i-1}])
    end
  end
  p_i = propnames{ind};
  
  % override the corresponding default in params
  params = setfield(params,p_i,v_i); %#ok
  
end


% ============================================
% subfunction - check_params
% ============================================
function params = check_params(params)

% check the parameters for acceptability
% smoothness == 1 by default
if isempty(params.smoothness)
  params.smoothness = 1;
else
  if (numel(params.smoothness)>2) || any(params.smoothness<=0)
    error 'Smoothness must be scalar (or length 2 vector), real, finite, and positive.'
  end
end

% regularizer  - must be one of 4 options - the second and
% third are actually synonyms.
valid = {'springs', 'diffusion', 'laplacian', 'gradient'};
if isempty(params.regularizer)
  params.regularizer = 'diffusion';
end
ind = find(strncmpi(params.regularizer,valid,length(params.regularizer)));
if (length(ind)==1)
  params.regularizer = valid{ind};
else
  error(['Invalid regularization method: ',params.regularizer])
end

% interp must be one of:
%    'bilinear', 'nearest', or 'triangle'
% but accept any shortening thereof.
valid = {'bilinear', 'nearest', 'triangle'};
if isempty(params.interp)
  params.interp = 'triangle';
end
ind = find(strncmpi(params.interp,valid,length(params.interp)));
if (length(ind)==1)
  params.interp = valid{ind};
else
  error(['Invalid interpolation method: ',params.interp])
end

% solver must be one of:
%    'backslash', '\', 'symmlq', 'lsqr', or 'normal'
% but accept any shortening thereof.
valid = {'backslash', '\', 'symmlq', 'lsqr', 'normal'};
if isempty(params.solver)
  params.solver = '\';
end
ind = find(strncmpi(params.solver,valid,length(params.solver)));
if (length(ind)==1)
  params.solver = valid{ind};
else
  error(['Invalid solver option: ',params.solver])
end

% extend must be one of:
%    'never', 'warning', 'always'
% but accept any shortening thereof.
valid = {'never', 'warning', 'always'};
if isempty(params.extend)
  params.extend = 'warning';
end
ind = find(strncmpi(params.extend,valid,length(params.extend)));
if (length(ind)==1)
  params.extend = valid{ind};
else
  error(['Invalid extend option: ',params.extend])
end

% tilesize == inf by default
if isempty(params.tilesize)
  params.tilesize = inf;
elseif (length(params.tilesize)>1) || (params.tilesize<3)
  error 'Tilesize must be scalar and > 0.'
end

% overlap == 0.20 by default
if isempty(params.overlap)
  params.overlap = 0.20;
elseif (length(params.overlap)>1) || (params.overlap<0) || (params.overlap>0.5)
  error 'Overlap must be scalar and 0 < overlap < 1.'
end

% ============================================
% subfunction - tiled_gridfit
% ============================================
function zgrid=tiled_gridfit(x,y,z,xnodes,ynodes,params)
% tiled_gridfit: a tiled version of gridfit, continuous across tile boundaries 
% usage: [zgrid,xgrid,ygrid]=tiled_gridfit(x,y,z,xnodes,ynodes,params)
%
% Tiled_gridfit is used when the total grid is far too large
% to model using a single call to gridfit. While gridfit may take
% only a second or so to build a 100x100 grid, a 2000x2000 grid
% will probably not run at all due to memory problems.
%
% Tiles in the grid with insufficient data (<4 points) will be
% filled with NaNs. Avoid use of too small tiles, especially
% if your data has holes in it that may encompass an entire tile.
%
% A mask may also be applied, in which case tiled_gridfit will
% subdivide the mask into tiles. Note that any boolean mask
% provided is assumed to be the size of the complete grid.
%
% Tiled_gridfit may not be fast on huge grids, but it should run
% as long as you use a reasonable tilesize. 8-)

% Note that we have already verified all parameters in check_params

% Matrix elements in a square tile
tilesize = params.tilesize;
% Size of overlap in terms of matrix elements. Overlaps
% of purely zero cause problems, so force at least two
% elements to overlap.
overlap = max(2,floor(tilesize*params.overlap));

% reset the tilesize for each particular tile to be inf, so
% we will never see a recursive call to tiled_gridfit
Tparams = params;
Tparams.tilesize = inf;

nx = length(xnodes);
ny = length(ynodes);
zgrid = zeros(ny,nx);

% linear ramp for the bilinear interpolation
rampfun = inline('(t-t(1))/(t(end)-t(1))','t');

% loop over each tile in the grid
h = waitbar(0,'Relax and have a cup of JAVA. Its my treat.');
warncount = 0;
xtind = 1:min(nx,tilesize);
while ~isempty(xtind) && (xtind(1)<=nx)
  
  xinterp = ones(1,length(xtind));
  if (xtind(1) ~= 1)
    xinterp(1:overlap) = rampfun(xnodes(xtind(1:overlap)));
  end
  if (xtind(end) ~= nx)
    xinterp((end-overlap+1):end) = 1-rampfun(xnodes(xtind((end-overlap+1):end)));
  end
  
  ytind = 1:min(ny,tilesize);
  while ~isempty(ytind) && (ytind(1)<=ny)
    % update the waitbar
    waitbar((xtind(end)-tilesize)/nx + tilesize*ytind(end)/ny/nx)
    
    yinterp = ones(length(ytind),1);
    if (ytind(1) ~= 1)
      yinterp(1:overlap) = rampfun(ynodes(ytind(1:overlap)));
    end
    if (ytind(end) ~= ny)
      yinterp((end-overlap+1):end) = 1-rampfun(ynodes(ytind((end-overlap+1):end)));
    end
    
    % was a mask supplied?
    if ~isempty(params.mask)
      submask = params.mask(ytind,xtind);
      Tparams.mask = submask;
    end
    
    % extract data that lies in this grid tile
    k = (x>=xnodes(xtind(1))) & (x<=xnodes(xtind(end))) & ...
        (y>=ynodes(ytind(1))) & (y<=ynodes(ytind(end)));
    k = find(k);
    
    if length(k)<4
      if warncount == 0
        warning('GRIDFIT:tiling','A tile was too underpopulated to model. Filled with NaNs.')
      end
      warncount = warncount + 1;
      
      % fill this part of the grid with NaNs
      zgrid(ytind,xtind) = NaN;
      
    else
      % build this tile
      zgtile = gridfit(x(k),y(k),z(k),xnodes(xtind),ynodes(ytind),Tparams);
      
      % bilinear interpolation (using an outer product)
      interp_coef = yinterp*xinterp;
      
      % accumulate the tile into the complete grid
      zgrid(ytind,xtind) = zgrid(ytind,xtind) + zgtile.*interp_coef;
      
    end
    
    % step to the next tile in y
    if ytind(end)<ny
      ytind = ytind + tilesize - overlap;
      % are we within overlap elements of the edge of the grid?
      if (ytind(end)+max(3,overlap))>=ny
        % extend this tile to the edge
        ytind = ytind(1):ny;
      end
    else
      ytind = ny+1;
    end
    
  end % while loop over y
  
  % step to the next tile in x
  if xtind(end)<nx
    xtind = xtind + tilesize - overlap;
    % are we within overlap elements of the edge of the grid?
    if (xtind(end)+max(3,overlap))>=nx
      % extend this tile to the edge
      xtind = xtind(1):nx;
    end
  else
    xtind = nx+1;
  end

end % while loop over x

% close down the waitbar
close(h)

if warncount>0
  warning('GRIDFIT:tiling',[num2str(warncount),' tiles were underpopulated & filled with NaNs'])
end

