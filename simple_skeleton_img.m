function ske = simple_skeleton_img(stackSize, nodes, edges)

% generate a 3d image starting from a node list (tree) representation
% original author: Sen Song, M.I.T.
% modified by Uygar Sumbul, M.I.T.

% inputs:
% stackSize: size of the imge stack (3 positive integers)
% nodes    : list of node xyz positions of the trace
% edges    : list of edges (node pairs) of the trace

% initialize ske image
ske=zeros(stackSize);
    
% draw every edge in tree
for i=1:size(edges,1),
    n1=nodes(edges(i,1),:);
    n2=nodes(edges(i,2),:);
    [y,x,z]=intline3( n1(1),n2(1),   n1(2), n2(2),   n1(3), n2(3));
    for j=1:length(x),
        ske(x(j),y(j),z(j))=1;
    end
end


function [x,y,z] = intline3(x1, x2, y1, y2, z1, z2)
%INTLINE Integer-coordinate line drawing algorithm.

dx = abs(x2 - x1); sx = sign(x2 - x1);
dy = abs(y2 - y1); sy = sign(y2 - y1);
dz = abs(z2 - z1); sz = sign(z2 - z1);

% Check for degenerate case.
if ((dx == 0) && (dy == 0) && (dz == 0))
        x = x1;
        y = y1;
        z = z1;
        return;
end

if (dx >= dy) && (dx >= dz)
        x = (x1:sx:x2).';
        m = (y2 - y1)/(x2 - x1);
        y = round(y1 + m*(x - x1));
        m = (z2 - z1)/(x2 - x1);
        z = round(z1 + m*(x - x1));
elseif (dy >= dx) && (dy >= dz)
        y = (y1:sy:y2).';
        m = (x2 - x1)/(y2 - y1);
        x = round(x1 + m*(y - y1));
        m = (z2 - z1)/(y2 - y1);
        z = round(z1 + m*(y - y1));
else
        z = (z1:sz:z2).';
        m = (x2 - x1)/(z2 - z1);
        x = round(x1 + m*(z - z1));
        m = (y2 - y1)/(z2 - z1);
        y = round(y1 + m*(z - z1));
end
