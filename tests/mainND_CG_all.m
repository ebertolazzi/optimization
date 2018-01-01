clear all;
close all;
clc;

addpath('../lib');
addpath('../functions');

fun_name = 'Rosen';
fplot    = @(z) log(1+z) ;
switch fun_name
case 'Quad'
  r  = Quadratic2D();
  RX = [-1.5 1.5] ;
  RY = [-1.5 1.5] ;
  x0 = [-1; 1 ];
  fplot = @(z) z ;
case 'Rosen'
  r  = Rosenbrock();
  RX = [-1.5 1.5] ;
  RY = [-0.4 1.5] ;
  x0 = [-1.2; 1 ];
case 'Bro'
  r  = Brown_bsf();
  RX = [0,4000] ;
  RY = [-600,600] ;
  x0 = 0.9*[ 10^6  ; 2*10^(-6) ] ;
end

disp(r.arity());

ls = 'Wolfe';
switch ls
case 'GS'
  search_method   = LinesearchGoldenSection();
  search_method.setTolerance( 1e-9 );
  search_method.setMaxIteration( int32(150) );
case 'Armijo'
  search_method = LinesearchArmijo();
case 'Wolfe'
  search_method = LinesearchWolfe();
end
search_method.debug_on();

%min_method = MinimizationGradientMethod(r,search_method);
min_method = MinimizationCG( r, search_method );

min_method.setMaxIteration( int32(1000) );
min_method.setTolerance(1e-8);
min_method.debug_on();

first = true ;
%for kk=2:14
for kk=2:14

  min_method.selectByNumber( int32(kk) );
  
  fprintf('\n\nMethod %s\n\n',min_method.activeMethod() );
  [xs,converged] = min_method.minimize( x0 ) ;

  if first
    
    subplot(2,1,1) ;
    r.contour(RX,RY,fplot,80);
    min_method.plotIter();
    axis equal ;

    subplot(2,1,2) ;
    min_method.plotResidual();
    first = false ;
  else
    subplot(2,1,2) ;
    hold on ;
    min_method.plotResidual();
  end
end

xs

