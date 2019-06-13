f = @(x) x;
N = 11; % number of points
K = 2; % order of spline

% first let's do a uniform grid, lower order
x = linspace(-1,1,N)';
spline_fit = InterpolatingSpline(x,f(x),K);

% dense grid to plot the interpolant
x_dense = linspace(-1,1,10*N)';

figure
subplot(1,2,1)
plot(x_dense,f(x_dense), 'k--', 'LineWidth', 2), hold on,
plot(x_dense,spline_fit(x_dense), 'LineWidth', 2)
scatter(x,f(x))

subplot(1,2,2)
plot(x_dense,2*f(x_dense), 'LineWidth', 2)

intspline = 2*spline_fit;

hold on
plot(x_dense,intspline(x_dense), 'LineWidth', 2)
