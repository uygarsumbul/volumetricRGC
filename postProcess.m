function stack = postProcess(stack, options)
% Software developed by: Uygar Sümbül <uygar@stat.columbia.edu, uygar@mit.edu>
% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.
% IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DAMAGES WHATSOEVER.
%
% postProcess a 3-d image stack to remove extraneous objects in the presence of a 'large' object of interest

if nargin < 2; options = []; end;
if ~isfield(options,'threshold') || isempty(options.threshold);                         threshold             = 0.8;            else; threshold = options.threshold; end;
if ~isfield(options,'conservativeThreshold') || isempty(options.conservativeThreshold); conservativeThreshold = 0.6;            else; conservativeThreshold = options.conservativeThreshold; end;
if ~isfield(options,'dilationRadius') || isempty(options.dilationRadius);               dilationRadius        = 6;              else; dilationRadius = options.dilationRadius; end;
if ~isfield(options,'dilationBase') || isempty(options.dilationBase);                   dilationBase          = dilationRadius; else; dilationBase = options.dilationBase; end;
if ~isfield(options,'dilationHeight') || isempty(options.dilationHeight);               dilationHeight        = 1;              else; dilationHeight = options.dilationHeight; end;
if ~isfield(options,'sizeThreshold') || isempty(options.sizeThreshold);                 sizeThreshold         = 50;             else; sizeThreshold = options.sizeThreshold; end;

% generate dilation kernel
dilationKernel = zeros(2*dilationBase+1,2*dilationBase+1,2*dilationHeight+1);
overallRadius = sqrt(dilationBase^2+dilationBase^2+dilationHeight^2);
[xx, yy, zz] = meshgrid(-dilationBase:dilationBase,-dilationBase:dilationBase,-dilationHeight:dilationHeight);
dilationKernel = sqrt(xx.^2+yy.^2+zz.^2)<=dilationRadius;

% make sure stack is between 0 and 1
stack = double(stack);
stack = stack - min(stack(:)); stack = stack/max(stack(:));

% binarize stack at threshold (a high value ensures noise is removed)
% dilate binarized stack - to ensure neuron remains connected
dilatedStack = imdilate(stack>threshold, dilationKernel);

% retain only the largest component
labels = bwlabeln(dilatedStack);
stats = regionprops(labels,'Area');
[~, ind] = sort([stats.Area], 'descend');
stack(labels~=ind(1)) = 0;

% binarize the resulting stack based on conservativeThreshold
stack = (stack>conservativeThreshold);

% remove components smaller than sizeThreshold
stack = bwareaopen(stack,sizeThreshold);
