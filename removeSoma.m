function vol = removeSoma(vol,options)
% Software developed by: Uygar Sümbül <uygar@stat.columbia.edu, uygar@mit.edu>
% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.
% IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DAMAGES WHATSOEVER.
%
% Remove the somata in the 3d binary image stack

if nargin < 2; options = []; end;
if ~isfield(options,'dilationRadius') || isempty(options.dilationRadius); dilationRadius = 5;              else; dilationRadius = options.dilationRadius; end;
if ~isfield(options,'dilationBase')   || isempty(options.dilationBase);   dilationBase   = dilationRadius; else; dilationBase = options.dilationBase; end;
if ~isfield(options,'dilationHeight') || isempty(options.dilationHeight); dilationHeight = 5;              else; dilationHeight = options.dilationHeight; end;

dilationKernel = zeros(2*dilationBase+1,2*dilationBase+1,2*dilationHeight+1);
overallRadius = sqrt(dilationBase^2+dilationBase^2+dilationHeight^2);
[xx, yy, zz] = meshgrid(-dilationBase:dilationBase,-dilationBase:dilationBase,-dilationHeight:dilationHeight);
dilationKernel = sqrt(xx.^2+yy.^2+zz.^2)<=dilationRadius;

vol = max(0,vol-imdilate(imopen(vol,dilationKernel),dilationKernel));
