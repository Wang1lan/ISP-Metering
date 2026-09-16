
%%  兼容MATLAB-R2018及以下版本
% 注意：运行时，命令行窗口出现黄色警告，可忽略，不影响程序正常运行。

%{
=========================UI说明==========================

用于导入内窥镜图像、按 Block 分块、对有效画面配置测光权重，
并生成 FPGA 可直接使用的权重文件。

---------------------------------------------------------

图像导入模块：点击“导入图像”选择原图，并在左侧显示原图；尺寸不能整除 Block 时，仅保留完整块区域。

Block 尺寸模块：提供 8×8、16×16、32×32、64×64 四档，默认 16×16；切换后重新生成权重矩阵。

有效画面模块：针对内窥镜四周黑边建立有效区域约束，黑边对应 Block 权重自动设为 0，主要对中心有效画面进行赋权。

权重设置模块：有效区域默认权重为 1，可选择权重 0至8，并通过框选 ROI 对对应 Block 批量赋值；后一次设置覆盖前一次。

矩阵预览模块：右侧显示 Block 网格及权重覆盖效果，便于直观看出各权重区域。

编辑模块：支持撤销上一次框选和重置全部框选，方便反复调整方案。

导出模块：最终权重矩阵转置后按列展开，导出为单列 TXT，使排列顺序符合 FPGA 按行扫描读取方式。
%}


%% UI界面代码
classdef MeterWeightSetting_V4_Compatibility < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure          matlab.ui.Figure
        Label_14          matlab.ui.control.Label
        Label_13          matlab.ui.control.Label
        Label_12          matlab.ui.control.Label
        Label_11          matlab.ui.control.Label
        Label_10          matlab.ui.control.Label
        Label_9           matlab.ui.control.Label
        Label_8           matlab.ui.control.Label
        Label_7           matlab.ui.control.Label
        Slider            matlab.ui.control.Slider
        Label_6           matlab.ui.control.Label
        Button_8          matlab.ui.control.Button
        Button_7          matlab.ui.control.Button
        BlockButtonGroup  matlab.ui.container.ButtonGroup
        Button_6          matlab.ui.control.ToggleButton
        Button_5          matlab.ui.control.ToggleButton
        Button_4          matlab.ui.control.ToggleButton
        Button_3          matlab.ui.control.ToggleButton
        Label_5           matlab.ui.control.Label
        Button_2          matlab.ui.control.Button
        Button_1          matlab.ui.control.Button
        TextArea          matlab.ui.control.TextArea
        Label             matlab.ui.control.Label
        UIAxes_2          matlab.ui.control.UIAxes
        UIAxes            matlab.ui.control.UIAxes
    end

    properties (Access = private)
        OriginalImage = []
        ValidImage = []
        SourceFilePath = ""
        BlockSize = 16
        OriginalImageSize = []
        ValidImageSize = []
        BlockRows = 0
        BlockCols = 0
        FovParams = struct()
        ValidBlockMask = false(0)
        FovOutlineHandle = []
        % Edit this configuration only for a known, calibrated imaging mode.
        FovConfig = struct('ReferenceHeight', 1080, 'ReferenceWidth', 1920, ...
            'ReferenceDiameter', 1440, 'Modes', struct('Height', {}, ...
            'Width', {}, 'CenterX', {}, 'CenterY', {}, 'Radius', {}, 'Source', {}))
        WeightMatrix = []
        UndoWeightMatrix = []
        BlockCenterX = []
        BlockCenterY = []
        CurrentWeight = 1
        OriginalImageHandle = []
        ValidImageHandle = []
        WeightOverlayHandle = []
        GridLineHandle = []
        WeightAxes = []
        WeightAxesLayoutListeners = {}
        IsSyncingWeightAxes = false
        SelectionCancelled = false
        SelectionFinished = false
        SelectionKeyCallback = []
        PreviousKeyPressFcn = []
        PreviousMotionFcn = []
        PreviousUpFcn = []
        SelectionPoints = []
        SelectionTraceHandle = []
        ActiveROI = []
        IsBusy = false
        IsDirty = false
    end

    properties (Constant, Access = private)
        WeightColors = [1 0 0; 0 0 0; 1 0.5 0.75; 1 0.5 0; ...
            1 1 0; 0 0.75 0; 0 1 1; 0 0.35 1; 0.6 0.2 0.8]
        WeightAlpha = [0.25; 0; 0.25; 0.25; 0.25; 0.25; 0.25; 0.25; 0.25]
        WeightNames = {'红','恢复默认','粉','橙','黄','绿','青','蓝','紫'}
    end

    methods (Access = private)
        function setIfSupported(~, obj, prop, value)
            % 旧版本无此属性或被 uifigure 禁用时静默跳过
            try
                obj.(prop) = value;
            catch
            end
        end

        function initializeWeightAxes(app)
            if isgraphics(app.WeightAxes, 'axes')
                app.syncWeightAxesLayout();
                return;
            end
            slot = app.UIAxes_2;
            ax = axes('Parent', slot.Parent, 'Units', slot.Units, ...
                'Visible', 'off', 'ActivePositionProperty', 'outerposition');
            try
                set(ax, 'OuterPosition', slot.Position, 'FontName', slot.FontName, ...
                    'FontSize', slot.FontSize, 'FontWeight', slot.FontWeight, ...
                    'FontAngle', slot.FontAngle, 'Color', 'none', ...
                    'XColor', slot.XColor, 'YColor', slot.YColor, 'Box', slot.Box);
                titleProperties = {'String','FontName','FontSize','FontWeight', ...
                    'FontAngle','Color'};
                set(ax.Title, titleProperties, get(slot.Title, titleProperties));
                disableDefaultInteractivity(ax);
                app.WeightAxes = ax;
                app.WeightAxesLayoutListeners = {};
                try
                    app.WeightAxesLayoutListeners{end+1} = addlistener(ax, 'OuterPosition', 'PostSet', ...
                        @(~,~)app.syncWeightAxesLayout());
                catch
                end
                try
                    app.WeightAxesLayoutListeners{end+1} = addlistener(slot, 'Position', 'PostSet', ...
                        @(~,~)app.syncWeightAxesLayout());
                catch
                end
                try
                    app.WeightAxesLayoutListeners{end+1} = addlistener(slot, 'Units', 'PostSet', ...
                        @(~,~)app.syncWeightAxesLayout());
                catch
                end
                % AutoResizeChildren may also reposition this runtime axes.
                try
                    app.WeightAxesLayoutListeners{end+1} = addlistener(app.UIFigure, ...
                        'ObjectBeingDestroyed', @(fig,~)app.cleanupWeightAxesResources(fig));
                catch
                end
                app.setIfSupported(app.UIFigure, 'SizeChangedFcn', @(~,~)app.onFigureSizeChanged());
                setappdata(app.UIFigure, 'MeterWeightAxesListeners', app.WeightAxesLayoutListeners);
                app.syncWeightAxesLayout();
                owned = [app.ValidImageHandle app.WeightOverlayHandle app.GridLineHandle];
                for k = 1:numel(owned)
                    if isgraphics(owned(k)) && isequal(owned(k).Parent, slot)
                        delete(owned(k));
                    end
                end
            catch exception
                app.cleanupWeightAxesResources();
                if isgraphics(ax), delete(ax); end
                app.WeightAxes = [];
                rethrow(exception);
            end
        end

        function ax = getWeightAxes(app)
            if isempty(app.WeightAxes) || ~isgraphics(app.WeightAxes, 'axes')
                error('MeterWeightSetting:WeightAxesNotInitialized', ...
                    '右侧绘图区尚未正确初始化，请关闭并重新打开应用。');
            end
            ax = app.WeightAxes;
        end

        function syncWeightAxesLayout(app)
            if ~isvalid(app) || app.IsSyncingWeightAxes || ...
                    ~isgraphics(app.UIAxes_2) || ~isgraphics(app.WeightAxes, 'axes')
                return;
            end
            app.IsSyncingWeightAxes = true;
            cleanup = onCleanup(@()app.finishWeightAxesLayout()); %#ok<NASGU>
            slot = app.UIAxes_2;
            ax = app.WeightAxes;
            ax.Units = slot.Units;
            ax.OuterPosition = slot.Position;
        end

        function finishWeightAxesLayout(app)
            if isvalid(app), app.IsSyncingWeightAxes = false; end
        end

        function onFigureSizeChanged(app)
            drawnow;
            app.syncWeightAxesLayout();
        end

        function cleanupWeightAxesResources(app, figureHandle)
            listeners = {};
            if isvalid(app)
                if nargin < 2, figureHandle = app.UIFigure; end
                app.restoreSelectionKeyCallback();
                app.cleanupActiveROI();
                listeners = app.WeightAxesLayoutListeners;
                app.WeightAxesLayoutListeners = {};
            end
            % AppBase can invalidate the app before its generated delete method
            % destroys UIFigure. Keep listener cleanup independent of app state.
            if nargin >= 2 || isvalid(app)
                if isgraphics(figureHandle) && isappdata(figureHandle, 'MeterWeightAxesListeners')
                    listeners = getappdata(figureHandle, 'MeterWeightAxesListeners');
                    rmappdata(figureHandle, 'MeterWeightAxesListeners');
                end
            end
            for k = 1:numel(listeners)
                if isvalid(listeners{k}), delete(listeners{k}); end
            end
        end

        function installSelectionKeyCallback(app)
            app.PreviousKeyPressFcn = app.UIFigure.WindowKeyPressFcn;
            app.SelectionKeyCallback = @(src,event)app.weightSelectionKeyPressed(src,event);
            app.UIFigure.WindowKeyPressFcn = app.SelectionKeyCallback;
        end

        function weightSelectionKeyPressed(app, src, event)
            if ~isvalid(app), return; end
            previous = app.PreviousKeyPressFcn;
            if strcmp(event.Key, 'escape'), app.SelectionCancelled = true; end
            % Preserve the previous application callback.
            if isa(previous, 'function_handle')
                previous(src, event);
            elseif iscell(previous) && ~isempty(previous)
                feval(previous{1}, src, event, previous{2:end});
            elseif ischar(previous) && ~isempty(previous)
                evalin('base', previous);
            end
        end

        function restoreSelectionKeyCallback(app)
            if ~isvalid(app), return; end
            if isgraphics(app.UIFigure) && ~isempty(app.SelectionKeyCallback) && ...
                    isequal(app.UIFigure.WindowKeyPressFcn, app.SelectionKeyCallback)
                app.UIFigure.WindowKeyPressFcn = app.PreviousKeyPressFcn;
            end
            app.SelectionKeyCallback = [];
            app.PreviousKeyPressFcn = [];
        end

        function markSelectionFinished(app)
            if isvalid(app), app.SelectionFinished = true; end
        end

        function installSelectionMouseCallbacks(app)
            app.PreviousMotionFcn = app.UIFigure.WindowButtonMotionFcn;
            app.PreviousUpFcn = app.UIFigure.WindowButtonUpFcn;
            app.UIFigure.WindowButtonMotionFcn = @(~,~)app.selectionMouseMoved();
            app.UIFigure.WindowButtonUpFcn = @(~,~)app.selectionMouseUp();
        end

        function restoreSelectionMouseCallbacks(app)
            if ~isvalid(app) || ~isgraphics(app.UIFigure), return; end
            app.UIFigure.WindowButtonMotionFcn = app.PreviousMotionFcn;
            app.UIFigure.WindowButtonUpFcn = app.PreviousUpFcn;
            app.PreviousMotionFcn = [];
            app.PreviousUpFcn = [];
        end

        function selectionMouseMoved(app)
            if ~app.IsBusy || isempty(app.SelectionPoints), return; end
            p = app.figureMouseDataPoint();
            if isempty(p) || any(~isfinite(p)), return; end
            app.SelectionPoints(end+1,:) = p;
            set(app.SelectionTraceHandle, 'XData', app.SelectionPoints(:,1), ...
                'YData', app.SelectionPoints(:,2));
        end

        function selectionMouseUp(app)
            if ~app.IsBusy, return; end
            app.restoreSelectionMouseCallbacks();
            app.finishSelection();
        end

        function finishSelection(app)
            if isgraphics(app.SelectionTraceHandle), delete(app.SelectionTraceHandle); end
            app.SelectionTraceHandle = [];
            points = app.SelectionPoints;
            app.SelectionPoints = [];
            operationWeight = app.CurrentWeight;
            if app.SelectionCancelled || isempty(points) || size(points,1) < 3 || ...
                    any(~isfinite(points(:))) || polyarea(points(:,1), points(:,2)) == 0
                app.finishOperation();
                return;
            end
            app.applySelectionPoints(points, operationWeight);
            app.finishOperation();
        end

        function p = figureMouseDataPoint(app)
            p = [];
            try
                cp = app.UIFigure.CurrentPoint;
                if isempty(cp), return; end
                fp = cp(1,1:2);
            catch
                return;
            end
            ax = app.UIAxes_2;
            if isprop(ax, 'InnerPosition'), box = ax.InnerPosition; else, box = ax.Position; end
            if numel(box) < 4 || box(3) <= 0 || box(4) <= 0, return; end
            xl = ax.XLim; yl = ax.YLim;
            xr = xl(2) - xl(1); yr = yl(2) - yl(1);
            if xr <= 0 || yr <= 0, return; end
            % 方形像素(DataAspectRatio=[1 1 1])会按数据宽高比居中 letterbox，
            % 据此计算实际绘图区(plot box)，保证像素→数据映射与显示一致。
            plotX = box(1); plotY = box(2); plotW = box(3); plotH = box(4);
            try
                if strcmpi(ax.DataAspectRatioMode, 'manual') && isequal(ax.DataAspectRatio, [1 1 1])
                    s = min(box(3) / xr, box(4) / yr);
                    plotW = s * xr; plotH = s * yr;
                    plotX = box(1) + (box(3) - plotW) / 2;
                    plotY = box(2) + (box(4) - plotH) / 2;
                end
            catch
            end
            rx = (fp(1) - plotX) / plotW;
            ry = (fp(2) - plotY) / plotH;
            x = xl(1) + rx * xr;
            if strcmpi(ax.YDir, 'reverse')
                y = yl(2) - ry * yr;
            else
                y = yl(1) + ry * yr;
            end
            p = [x y];
        end

        function reportError(app, exception)
            fprintf(2, '%s\n%s\n', exception.identifier, ...
                getReport(exception, 'extended', 'hyperlinks', 'off'));
            if isvalid(app), app.showError(exception.message); end
        end

        function model = initializeBlockModel(app, imageData, filePath, blockSize)
            if isempty(imageData) || ndims(imageData) > 3 || ...
                    ~ismember(size(imageData, 3), [1 3])
                error('MeterWeightSetting:ImageType', '请选择灰度或 RGB 图像。');
            end
            H = size(imageData, 1); W = size(imageData, 2);
            validH = floor(H / blockSize) * blockSize;
            validW = floor(W / blockSize) * blockSize;
            if validH == 0 || validW == 0
                error('MeterWeightSetting:ImageTooSmall', '图像小于所选 block，无法形成完整 block。');
            end
            model.FovParams = app.resolveFovParameters(H, W, app.FovConfig);
            model.OriginalImage = imageData;
            model.ValidImage = imageData(1:validH, 1:validW, :);
            model.SourceFilePath = filePath;
            model.BlockSize = blockSize;
            model.OriginalImageSize = size(imageData);
            model.ValidImageSize = size(model.ValidImage);
            model.BlockRows = validH / blockSize;
            model.BlockCols = validW / blockSize;
            model.ValidBlockMask = app.buildValidBlockMask(model.BlockRows, ...
                model.BlockCols, blockSize, model.FovParams);
            if ~any(model.ValidBlockMask(:))
                error('MeterWeightSetting:NoValidBlocks', ...
                    '当前视场及 block 尺寸下没有完整有效块。');
            end
            model.WeightMatrix = double(model.ValidBlockMask);
            app.validateWeightMatrix(model.WeightMatrix, model.ValidBlockMask, ...
                model.BlockRows, model.BlockCols);
            [model.BlockCenterX, model.BlockCenterY] = meshgrid( ...
                ((1:model.BlockCols) - 0.5) * blockSize + 0.5, ...
                ((1:model.BlockRows) - 0.5) * blockSize + 0.5);
            model.IsDirty = false;
        end

        function params = resolveFovParameters(app, H, W, config) %#ok<INUSD>
            modes = config.Modes;
            match = find([modes.Height] == H & [modes.Width] == W);
            if numel(match) > 1
                error('MeterWeightSetting:InvalidFovConfig', '当前分辨率的有效视场配置重复。');
            elseif ~isempty(match)
                mode = modes(match);
                params = struct('CenterX', mode.CenterX, 'CenterY', mode.CenterY, ...
                    'Radius', mode.Radius, 'Source', mode.Source);
            else
                reference = [config.ReferenceHeight config.ReferenceWidth config.ReferenceDiameter];
                validateattributes(reference, {'double'}, {'real','finite','positive','numel',3});
                sx = W / config.ReferenceWidth; sy = H / config.ReferenceHeight;
                if abs(sx-sy) > 1e-6 * max([1 sx sy])
                    error('MeterWeightSetting:FovNotConfigured', ...
                        '此分辨率尚未配置有效视场参数（宽%d，高%d）。', W, H);
                end
                params = struct('CenterX', (W+1)/2, 'CenterY', (H+1)/2, ...
                    'Radius', config.ReferenceDiameter*sx/2, 'Source', 'reference-scaled');
            end
            validateattributes(params.CenterX, {'numeric'}, {'real','finite','scalar'});
            validateattributes(params.CenterY, {'numeric'}, {'real','finite','scalar'});
            validateattributes(params.Radius, {'numeric'}, {'real','finite','scalar','positive'});
        end

        function mask = buildValidBlockMask(app, rows, cols, B, params) %#ok<INUSD>
            x0 = (0:cols-1)*B + 1; x1 = x0 + B - 1;
            y0 = (0:rows-1)*B + 1; y1 = y0 + B - 1;
            dx = max(abs(x0-params.CenterX), abs(x1-params.CenterX));
            dy = max(abs(y0-params.CenterY), abs(y1-params.CenterY));
            mask = bsxfun(@plus, dy(:).^2, dx(:).'.^2) <= params.Radius^2;
        end

        function edited = hasEditedWeights(app)
            edited = false;
            if isempty(app.WeightMatrix), return; end
            % UI state must remain usable so commit/export can report bad data.
            edited = ~isequal(app.WeightMatrix, double(app.ValidBlockMask));
        end

        function renderImages(app)
            rightAx = app.UIAxes_2;
            % Create replacement graphics before removing the old preview.
            oldHandles = [app.OriginalImageHandle, app.ValidImageHandle, ...
                app.WeightOverlayHandle, app.GridLineHandle, app.FovOutlineHandle];
            newHandles = gobjects(0);
            axesProperties = {'XLim','YLim','YDir','DataAspectRatio','XTick','YTick','CLim','Colormap','View'};
            oldOriginalAxes = get(app.UIAxes, axesProperties);
            oldValidAxes = get(rightAx, axesProperties);
            try, oldTitle = rightAx.Title.String; catch, oldTitle = ''; end
            try
                hOriginal = image(app.UIAxes, 'CData', app.OriginalImage, ...
                    'CDataMapping', 'scaled', 'Visible', 'off');
                newHandles(end+1) = hOriginal;
                hValid = image(rightAx, 'CData', app.ValidImage, ...
                    'CDataMapping', 'scaled', 'Visible', 'off', ...
                    'HitTest', 'on', 'PickableParts', 'all', ...
                    'ButtonDownFcn', @(~,event)app.startWeightSelection(event));
                newHandles(end+1) = hValid;
                [colors, alpha] = app.weightOverlayData();
                x = [app.BlockCenterX(1,1), app.BlockCenterX(1,end)];
                y = [app.BlockCenterY(1,1), app.BlockCenterY(end,1)];
                % MATLAB gives a singleton image cell three times its X/YData span.
                % Choose that span so its outer edges still match the one block.
                if app.BlockCols == 1, x = 0.5 + app.BlockSize * [1/3 2/3]; end
                if app.BlockRows == 1, y = 0.5 + app.BlockSize * [1/3 2/3]; end
                hOverlay = image(rightAx, 'CData', colors, ...
                    'XData', x, 'YData', y, 'AlphaData', alpha, ...
                    'AlphaDataMapping', 'none', 'Visible', 'off', ...
                    'HitTest', 'off', 'PickableParts', 'none');
                newHandles(end+1) = hOverlay;
                [gx, gy] = app.createGridLineData();
                hGrid = line(rightAx, gx, gy, 'Color', [0.55 0.55 0.55], ...
                    'LineWidth', 0.5, 'Visible', 'off', ...
                    'HitTest', 'off', 'PickableParts', 'none');
                newHandles(end+1) = hGrid;
                theta = linspace(0, 2*pi, 721);
                hFov = line(rightAx, app.FovParams.CenterX + app.FovParams.Radius*cos(theta), ...
                    app.FovParams.CenterY + app.FovParams.Radius*sin(theta), ...
                    'Color', [0.9 0.9 0.9], 'LineStyle', '--', 'LineWidth', 0.75, ...
                    'Clipping', 'on', 'Visible', 'off', 'HitTest', 'off', 'PickableParts', 'none');
                newHandles(end+1) = hFov;
                app.configureImageAxes(app.UIAxes, app.OriginalImage);
                app.configureImageAxes(rightAx, app.ValidImage);
                app.configureImageAxes(app.WeightAxes, app.ValidImage);
                app.updateRightAxesTitle();
                set(newHandles, 'Visible', 'on');
            catch exception
                delete(newHandles(isgraphics(newHandles)));
                if isvalid(app) && isgraphics(app.UIFigure)
                    set(app.UIAxes, axesProperties, oldOriginalAxes);
                    set(rightAx, axesProperties, oldValidAxes);
                    try, rightAx.Title.String = oldTitle; catch, end
                end
                rethrow(exception);
            end
            delete(oldHandles(isgraphics(oldHandles)));
            app.OriginalImageHandle = hOriginal;
            app.ValidImageHandle = hValid;
            app.WeightOverlayHandle = hOverlay;
            app.GridLineHandle = hGrid;
            app.FovOutlineHandle = hFov;

        end

        function configureImageAxes(app, ax, img) %#ok<INUSD>
            ax.XLim = [0.5 size(img,2)+0.5];
            ax.YLim = [0.5 size(img,1)+0.5];
            ax.YDir = 'reverse';
            try, ax.View = [0 90]; catch, end
            try, ax.DataAspectRatio = [1 1 1]; catch, end
            ax.XTick = [];
            ax.YTick = [];
            colormap(ax, gray(256));
            if isinteger(img)
                ax.CLim = [double(intmin(class(img))), double(intmax(class(img)))];
            else
                ax.CLim = [0 1];
            end
            try, disableDefaultInteractivity(ax); catch, end
        end

        function [colors, alpha] = weightOverlayData(app)
            app.validateWeightMatrix(app.WeightMatrix);
            index = app.WeightMatrix(:) + 1;
            rgb = app.WeightColors(index,:);
            rgb(~app.ValidBlockMask(:),:) = repmat([0.35 0.35 0.35], nnz(~app.ValidBlockMask), 1);
            colors = reshape(rgb, app.BlockRows, app.BlockCols, 3);
            alpha = reshape(app.WeightAlpha(index), app.BlockRows, app.BlockCols);
            alpha(~app.ValidBlockMask) = 0.30;
        end

        function validateWeightMatrix(app, weights, mask, rows, cols)
            if nargin == 2
                mask = app.ValidBlockMask; rows = app.BlockRows; cols = app.BlockCols;
            end
            if ~isa(weights, 'double') || ~isreal(weights) || isempty(weights) || ...
                    ~ismatrix(weights) || ~isequal(size(weights), [rows cols]) || ...
                    any(~isfinite(weights(:))) || any(weights(:) ~= round(weights(:))) || ...
                    any(weights(:) < 0 | weights(:) > 8)
                error('MeterWeightSetting:InvalidWeights', ...
                    '权重矩阵必须与当前分块尺寸一致，且为0～8有限整数的double二维矩阵。');
            end
            if ~islogical(mask) || ~isequal(size(weights), size(mask)) || any(weights(~mask) ~= 0)
                error('MeterWeightSetting:InvalidFovWeights', ...
                    '有效块掩模必须与权重矩阵同尺寸，且所有无效 block 的权重必须为0。');
            end
        end

        function weight = quantizeWeight(app, rawValue) %#ok<INUSD>
            if ~isnumeric(rawValue) || ~isreal(rawValue) || ~isscalar(rawValue) || ~isfinite(rawValue)
                error('MeterWeightSetting:InvalidSliderValue', '请选择0～8的有限数值权重。');
            end
            weight = min(8, max(0, round(double(rawValue))));
        end

        function refreshWeightOverlay(app)
            [colors, alpha] = app.weightOverlayData();
            set(app.WeightOverlayHandle, 'CData', colors, 'AlphaData', alpha);
        end

        function [x, y] = createGridLineData(app)
            width = app.ValidImageSize(2);
            height = app.ValidImageSize(1);
            xb = 0.5 + (0:app.BlockCols) * app.BlockSize;
            yb = 0.5 + (0:app.BlockRows) * app.BlockSize;
            vx = [xb; xb; nan(size(xb))];
            vy = [0.5*ones(size(xb)); (height+0.5)*ones(size(xb)); nan(size(xb))];
            hx = [0.5*ones(size(yb)); (width+0.5)*ones(size(yb)); nan(size(yb))];
            hy = [yb; yb; nan(size(yb))];
            x = [vx(:); hx(:)];
            y = [vy(:); hy(:)];
        end

        function startWeightSelection(app, event)
            if ~isvalid(app) || ~isgraphics(app.UIFigure) || app.IsBusy || ...
                    isempty(app.WeightMatrix) || ~strcmp(app.UIFigure.SelectionType, 'normal')
                return;
            end
            try
                if isempty(event) || ~isprop(event, 'IntersectionPoint'), return; end
                startPoint = event.IntersectionPoint(1:2);
                if any(~isfinite(startPoint)) || any(startPoint < 0.5) || ...
                        startPoint(1) > app.ValidImageSize(2)+0.5 || ...
                        startPoint(2) > app.ValidImageSize(1)+0.5
                    return;
                end
                operationWeight = app.CurrentWeight;
                app.IsBusy = true;
                app.SelectionCancelled = false;
                app.updateControlState();
                if app.quantizeWeight(operationWeight) ~= operationWeight
                    error('MeterWeightSetting:InvalidSliderValue', '圈选权重必须为0～8整数。');
                end
                app.installSelectionKeyCallback();
                % 手动自由圈选：轨迹画在 uiaxes 上，与显示同层、无漂移且可见
                app.SelectionPoints = startPoint;
                roiColor = app.WeightColors(operationWeight+1,:);
                if operationWeight == 1, roiColor = [1 1 1]; end
                app.SelectionTraceHandle = line(app.UIAxes_2, startPoint(1), startPoint(2), ...
                    'Color', roiColor, 'LineWidth', 2, 'HitTest', 'off', 'PickableParts', 'none');
                app.installSelectionMouseCallbacks();
            catch exception
                if app.IsBusy, app.finishOperation(); end
                app.reportError(exception);
            end
        end

        function applySelectionPoints(app, points, operationWeight)
            if app.SelectionCancelled || isempty(points) || size(points,1) < 3 || ...
                    any(~isfinite(points(:))) || polyarea(points(:,1), points(:,2)) == 0
                return;
            end
            if app.quantizeWeight(operationWeight) ~= operationWeight
                error('MeterWeightSetting:InvalidSliderValue', '圈选权重必须为0～8整数。');
            end
            selected = reshape(inpolygon(app.BlockCenterX(:), app.BlockCenterY(:), ...
                points(:,1), points(:,2)), app.BlockRows, app.BlockCols) & app.ValidBlockMask;
            if any(app.WeightMatrix(selected) ~= operationWeight)
                before = app.WeightMatrix;
                after = before;
                after(selected) = operationWeight;
                app.commitWeights(after, before, true);
            end
        end



        function updateControlState(app)
            if ~isvalid(app) || ~isgraphics(app.UIFigure), return; end
            idle = ~app.IsBusy;
            hasImage = ~isempty(app.WeightMatrix);
            hasUndo = ~isempty(app.UndoWeightMatrix);
            hasWeights = hasImage && app.hasEditedWeights();
            app.Button_1.Enable = matlab.lang.OnOffSwitchState(idle);
            set([app.Button_3 app.Button_4 app.Button_5 app.Button_6], ...
                'Enable', matlab.lang.OnOffSwitchState(idle));
            enabled = matlab.lang.OnOffSwitchState(idle && hasImage);
            app.Button_2.Enable = enabled;
            app.Slider.Enable = matlab.lang.OnOffSwitchState(idle);
            app.Button_7.Enable = matlab.lang.OnOffSwitchState(idle && hasImage && hasUndo);
            app.Button_8.Enable = matlab.lang.OnOffSwitchState(idle && hasImage && (hasWeights || hasUndo));
            app.syncBlockSizeButtons();
        end

        function finishOperation(app)
            if ~isvalid(app), return; end
            app.restoreSelectionKeyCallback();
            app.restoreSelectionMouseCallbacks();
            if isgraphics(app.SelectionTraceHandle), delete(app.SelectionTraceHandle); end
            app.SelectionTraceHandle = [];
            app.cleanupActiveROI();
            app.IsBusy = false;
            app.SelectionCancelled = false;
            app.SelectionFinished = false;
            if isgraphics(app.UIFigure), app.updateControlState(); end
        end

        function cleanupActiveROI(app)
            if ~isvalid(app), return; end
            roi = app.ActiveROI;
            app.ActiveROI = [];
            if ~isempty(roi) && isvalid(roi), delete(roi); end
        end

        function resetAllWeights(app)
            if app.IsBusy || isempty(app.WeightMatrix), return; end
            changed = app.hasEditedWeights();
            if ~changed && isempty(app.UndoWeightMatrix), return; end
            app.IsBusy = true;
            cleanup = onCleanup(@()app.finishOperation()); %#ok<NASGU>
            app.updateControlState();
            try
                choice = uiconfirm(app.UIFigure, ...
                    '将有效 block 的权重恢复为1，无效 block 保持为0，并清空撤销记录。当前圈选权重保留；该重置不可撤销，是否继续？', ...
                    '重置所有框选', 'Options', {'重置', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~isvalid(app) || ~isgraphics(app.UIFigure), return; end
                if strcmp(choice, '重置')
                    app.commitWeights(double(app.ValidBlockMask), [], app.IsDirty || changed);
                end
            catch exception
                app.reportError(exception);
            end
        end

        function updateRightAxesTitle(app)
            hint = sprintf('当前权重=%d（%s）', app.CurrentWeight, app.WeightNames{app.CurrentWeight+1});
            app.Slider.Tooltip = [hint '；左键拖动圈选；权重1恢复有效块默认值'];
            if isempty(app.WeightMatrix), return; end
            title(app.UIAxes_2, {sprintf('Block权重矩阵 | B=%d | %d×%d | 有效块=%d | %s', ...
                app.BlockSize, app.BlockRows, app.BlockCols, nnz(app.ValidBlockMask), hint), ...
                sprintf('FOV 圆心=(%.1f, %.1f)，直径=%.1f px；灰色块固定0', ...
                app.FovParams.CenterX, app.FovParams.CenterY, 2*app.FovParams.Radius)}, ...
                'Interpreter', 'none');
        end

        function syncBlockSizeButtons(app)
            buttons = [app.Button_3 app.Button_4 app.Button_5 app.Button_6];
            sizes = [8 16 32 64];
            selected = buttons(sizes == app.BlockSize);
            app.BlockButtonGroup.SelectedObject = selected;
            set(buttons, 'BackgroundColor', [0.96 0.96 0.96]);
            selected.BackgroundColor = [0.5333 0.7412 0.6431];
        end

        function applyBlockModel(app, model)
            app.validateWeightMatrix(model.WeightMatrix, model.ValidBlockMask, ...
                model.BlockRows, model.BlockCols);
            fields = fieldnames(model);
            previous = struct();
            previousUndo = app.UndoWeightMatrix;
            for k = 1:numel(fields)
                previous.(fields{k}) = app.(fields{k});
            end
            try
                for k = 1:numel(fields), app.(fields{k}) = model.(fields{k}); end
                app.renderImages();
                app.clearUndoRecord();
            catch exception
                if isvalid(app)
                    for k = 1:numel(fields), app.(fields{k}) = previous.(fields{k}); end
                    app.UndoWeightMatrix = previousUndo;
                end
                rethrow(exception);
            end
        end

        function commitWeights(app, after, undoMatrix, dirty)
            app.validateWeightMatrix(after);
            if ~isempty(undoMatrix), app.validateWeightMatrix(undoMatrix); end
            before = app.WeightMatrix;
            previousUndo = app.UndoWeightMatrix;
            previousDirty = app.IsDirty;
            try
                app.WeightMatrix = after;
                app.refreshWeightOverlay();
                app.UndoWeightMatrix = undoMatrix;
                app.IsDirty = dirty;
            catch exception
                if isvalid(app)
                    app.WeightMatrix = before;
                    app.UndoWeightMatrix = previousUndo;
                    app.IsDirty = previousDirty;
                    if isgraphics(app.UIFigure)
                        try
                            app.refreshWeightOverlay();
                        catch restoreException
                            exception = addCause(exception, restoreException);
                        end
                    end
                end
                rethrow(exception);
            end
        end

        function clearUndoRecord(app)
            app.UndoWeightMatrix = [];
        end

        function undoLastSelection(app)
            if app.IsBusy || isempty(app.WeightMatrix) || isempty(app.UndoWeightMatrix), return; end
            app.IsBusy = true;
            cleanup = onCleanup(@()app.finishOperation()); %#ok<NASGU>
            app.updateControlState();
            try
                app.commitWeights(app.UndoWeightMatrix, [], true);
            catch exception
                app.reportError(exception);
            end
        end

        function changeBlockSize(app, selectedButton)
            if app.IsBusy
                app.syncBlockSizeButtons();
                return;
            end
            buttons = [app.Button_3 app.Button_4 app.Button_5 app.Button_6];
            sizes = [8 16 32 64];
            newSize = sizes(buttons == selectedButton);
            if isempty(newSize) || newSize == app.BlockSize
                app.syncBlockSizeButtons();
                return;
            end
            if isempty(app.OriginalImage)
                app.BlockSize = newSize;
                app.syncBlockSizeButtons();
                return;
            end
            app.IsBusy = true;
            cleanup = onCleanup(@()app.finishOperation()); %#ok<NASGU>
            app.updateControlState();
            try
                model = app.initializeBlockModel(app.OriginalImage, app.SourceFilePath, newSize);
                if app.hasEditedWeights() || ~isempty(app.UndoWeightMatrix)
                    choice = uiconfirm(app.UIFigure, ...
                        '更改 block 尺寸将重置所有权重并清空撤销记录，是否继续？', ...
                        '更改 block 尺寸', 'Options', {'继续', '取消'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~isvalid(app) || ~isgraphics(app.UIFigure) || ~strcmp(choice, '继续')
                        return;
                    end
                end
                model.IsDirty = true;
                app.applyBlockModel(model);
            catch exception
                app.reportError(exception);
            end
        end

        function vector = serializeWeights(app, weights)
            app.validateWeightMatrix(weights);
            vector = reshape(weights.', [], 1);
        end

        function writeWeightText(app, targetPath, vector) %#ok<INUSD>
            folder = fileparts(targetPath);
            if isempty(folder), folder = pwd; end
            if exist(targetPath, 'dir') == 7
                error('MeterWeightSetting:ExportTarget', '目标路径是文件夹，无法保存 TXT。');
            end
            if exist(targetPath, 'file') == 2
                [ok, attributes] = fileattrib(targetPath);
                if ~ok || ~attributes.UserWrite
                    error('MeterWeightSetting:ExportReadOnly', '目标文件为只读，无法覆盖。');
                end
            end
            temporaryPath = [tempname(folder) '.tmp'];
            fid = -1;
            try
                [fid, message] = fopen(temporaryPath, 'wb');
                if fid < 0, error('MeterWeightSetting:ExportOpen', '无法打开临时文件：%s', message); end
                written = fprintf(fid, '%d\n', vector);
                [message, errorNumber] = ferror(fid);
                if written ~= 2*numel(vector) || errorNumber ~= 0
                    error('MeterWeightSetting:ExportWrite', 'TXT 写入不完整：%s', message);
                end
                closeStatus = fclose(fid); fid = -1;
                if closeStatus ~= 0
                    error('MeterWeightSetting:ExportClose', '无法完整关闭 TXT 临时文件。');
                end
                % Same-directory rename after close; never delete the destination first.
                [ok, message] = movefile(temporaryPath, targetPath, 'f');
                if ~ok, error('MeterWeightSetting:ExportReplace', '无法保存 TXT：%s', message); end
            catch exception
                if fid >= 0, fclose(fid); end
                if exist(temporaryPath, 'file') == 2, delete(temporaryPath); end
                rethrow(exception);
            end
        end

        function showError(app, message)
            if isvalid(app) && isgraphics(app.UIFigure)
                uialert(app.UIFigure, message, '操作提示');
            end
        end
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.initializeWeightAxes();
            app.BlockSize = 16;
            app.BlockButtonGroup.SelectedObject = app.Button_4;
            app.Button_7.Tooltip = '仅撤销最近一次有效赋权';
            app.Label_5.Tooltip = '有效 block 默认权重为1；黑边及边界混合 block 固定为0。圈选仅对有效 block 生效。';
            app.Slider.Limits = [0 8];
            app.Slider.MajorTicks = 0:8;
            app.setIfSupported(app.Slider, 'MajorTickLabels', cellstr(string(0:8)));
            app.Slider.MinorTicks = [];
            app.setIfSupported(app.Slider, 'Step', 1);
            app.Slider.Value = 1;
            app.CurrentWeight = 1;
            app.clearUndoRecord();
            app.updateRightAxesTitle();
            app.updateControlState();
        end

        % Value changed function: Slider
        function SliderValueChanged(app, event)
            if app.IsBusy
                app.Slider.Value = app.CurrentWeight;
                return;
            end
            try
                weight = app.quantizeWeight(event.Value);
                app.Slider.Value = weight;
                app.CurrentWeight = weight;
                app.updateRightAxesTitle();
            catch exception
                app.Slider.Value = app.CurrentWeight;
                app.reportError(exception);
            end
        end

        % Button pushed function: Button_1
        function ImportImageButtonPushed(app, event)
            if app.IsBusy, return; end
            app.IsBusy = true;
            cleanup = onCleanup(@()app.finishOperation()); %#ok<NASGU>
            app.updateControlState();
            try
                if app.IsDirty
                    choice = uiconfirm(app.UIFigure, '放弃未导出的权重修改并重新导入？', ...
                        '重新导入', 'Options', {'放弃并导入', '取消'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~isvalid(app) || ~isgraphics(app.UIFigure) || ~strcmp(choice, '放弃并导入')
                        return;
                    end
                end
                [name, folder] = uigetfile( ...
                    {'*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff', '图像文件 (PNG/JPEG/BMP/TIFF)'}, '导入图像');
                if isequal(name, 0), return; end
                filePath = fullfile(folder, name);
                [img, map] = imread(filePath);
                if ~isempty(map), img = ind2rgb(img, map); end
                if ~isvalid(app) || ~isgraphics(app.UIFigure), return; end
                model = app.initializeBlockModel(img, filePath, app.BlockSize);
                app.applyBlockModel(model);
            catch exception
                app.reportError(exception);
            end
        end

        % Button pushed function: Button_2
        function ExportWeightMatrixButtonPushed(app, event)
            if app.IsBusy, return; end
            if isempty(app.WeightMatrix)
                app.showError('请先导入图像。');
                return;
            end
            app.IsBusy = true;
            cleanup = onCleanup(@()app.finishOperation()); %#ok<NASGU>
            app.updateControlState();
            try
                exportVector = app.serializeWeights(app.WeightMatrix);
                [folder, name] = fileparts(app.SourceFilePath);
                defaultName = fullfile(folder, sprintf('%s_weight_W%d_H%d_B%d_R%d_C%d.txt', ...
                    name, app.OriginalImageSize(2), app.OriginalImageSize(1), ...
                    app.BlockSize, app.BlockRows, app.BlockCols));
                [fileName, pathName] = uiputfile({'*.txt', '权重 TXT 文件'}, '导出权重 TXT', defaultName);
                if isequal(fileName, 0) || ~isvalid(app) || ~isgraphics(app.UIFigure), return; end
                [~, stem] = fileparts(fileName);
                targetPath = fullfile(pathName, [stem '.txt']);
                if exist(targetPath, 'file') == 2
                    choice = uiconfirm(app.UIFigure, sprintf('文件已存在，是否覆盖？\n%s', targetPath), ...
                        '覆盖 TXT 文件', 'Options', {'覆盖', '取消'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~isvalid(app) || ~isgraphics(app.UIFigure) || ~strcmp(choice, '覆盖'), return; end
                end
                app.writeWeightText(targetPath, exportVector);
                app.IsDirty = false;
                if all(exportVector == 0)
                    uialert(app.UIFigure, '全0权重不能直接用于归一化加权测光。', ...
                        '导出提示', 'Icon', 'warning');
                end
            catch exception
                app.reportError(exception);
            end
        end

        % Close request function: UIFigure
        function UIFigureCloseRequest(app, event)
            app.cleanupWeightAxesResources();
            delete(app);
        end

        % Selection changed function: BlockButtonGroup
        function BlockButtonGroupSelectionChanged(app, event)
            app.changeBlockSize(event.NewValue);
        end

        % Button pushed function: Button_7
        function UndoLastSelectionButtonPushed(app, event)
            app.undoLastSelection();
        end

        % Button pushed function: Button_8
        function ResetAllSelectionsButtonPushed(app, event)
            app.resetAllWeights();
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Color = [0.949 0.9373 0.9059];
            app.UIFigure.Position = [100 100 1274 702];
            app.UIFigure.Name = 'MATLAB App';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @UIFigureCloseRequest, true);

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, '原图')
            app.UIAxes.XColor = 'none';
            app.UIAxes.XTick = [];
            app.UIAxes.YColor = 'none';
            app.UIAxes.YTick = [];
            app.UIAxes.FontSize = 12;
            app.UIAxes.Position = [21 468 211 184];

            % Create UIAxes_2
            app.UIAxes_2 = uiaxes(app.UIFigure);
            title(app.UIAxes_2, 'Block权重矩阵')
            app.UIAxes_2.XColor = 'none';
            app.UIAxes_2.XTick = [];
            app.UIAxes_2.YColor = 'none';
            app.UIAxes_2.YTick = [];
            app.UIAxes_2.FontSize = 12;
            app.UIAxes_2.Position = [306 22 967 604];

            % Create Label
            app.Label = uilabel(app.UIFigure);
            app.Label.BackgroundColor = [0.4667 0.5333 0.451];
            app.Label.HorizontalAlignment = 'right';
            app.Label.FontName = '微软雅黑';
            app.Label.FontSize = 20;
            app.Label.FontWeight = 'bold';
            app.Label.Position = [31 674 25 27];
            app.Label.Text = '';

            % Create TextArea
            app.TextArea = uitextarea(app.UIFigure);
            app.TextArea.HorizontalAlignment = 'center';
            app.TextArea.FontName = '微软雅黑';
            app.TextArea.FontSize = 20;
            app.TextArea.FontWeight = 'bold';
            app.TextArea.FontColor = [1 1 1];
            app.TextArea.BackgroundColor = [0.4667 0.5333 0.451];
            app.TextArea.Position = [1 660 1274 43];
            app.TextArea.Value = {'自动测光Block权重赋予界面'};

            % Create Button_1
            app.Button_1 = uibutton(app.UIFigure, 'push');
            app.Button_1.ButtonPushedFcn = createCallbackFcn(app, @ImportImageButtonPushed, true);
            app.Button_1.BackgroundColor = [0.8627 0.8118 0.7529];
            app.Button_1.Position = [33 388 91 30];
            app.Button_1.Text = '导入图像';

            % Create Button_2
            app.Button_2 = uibutton(app.UIFigure, 'push');
            app.Button_2.ButtonPushedFcn = createCallbackFcn(app, @ExportWeightMatrixButtonPushed, true);
            app.Button_2.BackgroundColor = [0.8627 0.8118 0.7529];
            app.Button_2.Position = [34 337 91 30];
            app.Button_2.Text = '导出权重 TXT';

            % Create Label_5
            app.Label_5 = uilabel(app.UIFigure);
            app.Label_5.HorizontalAlignment = 'center';
            app.Label_5.FontWeight = 'bold';
            app.Label_5.FontColor = [1 0 0];
            app.Label_5.Position = [25 124 73 38];
            app.Label_5.Text = {'有效块默认1'; '黑边块固定0'};

            % Create BlockButtonGroup
            app.BlockButtonGroup = uibuttongroup(app.UIFigure);
            app.BlockButtonGroup.SelectionChangedFcn = createCallbackFcn(app, @BlockButtonGroupSelectionChanged, true);
            app.BlockButtonGroup.BorderType = 'none';
            app.BlockButtonGroup.TitlePosition = 'centertop';
            app.BlockButtonGroup.Title = 'Block尺寸设置';
            app.BlockButtonGroup.BackgroundColor = [0.949 0.9373 0.9059];
            app.BlockButtonGroup.FontWeight = 'bold';
            app.BlockButtonGroup.Position = [157 244 130 158];

            % Create Button_3
            app.Button_3 = uitogglebutton(app.BlockButtonGroup);
            app.Button_3.IconAlignment = 'center';
            app.Button_3.Text = '[8, 8]';
            app.Button_3.Position = [15 107 100 22];

            % Create Button_4
            app.Button_4 = uitogglebutton(app.BlockButtonGroup);
            app.Button_4.Text = '[16, 16]';
            app.Button_4.BackgroundColor = [0.5333 0.7412 0.6431];
            app.Button_4.Position = [15 74 100 22];
            app.Button_4.Value = true;

            % Create Button_5
            app.Button_5 = uitogglebutton(app.BlockButtonGroup);
            app.Button_5.Text = '[32, 32]';
            app.Button_5.Position = [15 43 100 22];

            % Create Button_6
            app.Button_6 = uitogglebutton(app.BlockButtonGroup);
            app.Button_6.Text = '[64, 64]';
            app.Button_6.Position = [15 12 100 22];

            % Create Button_7
            app.Button_7 = uibutton(app.UIFigure, 'push');
            app.Button_7.ButtonPushedFcn = createCallbackFcn(app, @UndoLastSelectionButtonPushed, true);
            app.Button_7.BackgroundColor = [0.8627 0.8118 0.7529];
            app.Button_7.Position = [34 286 90 30];
            app.Button_7.Text = '撤销上个圈选';

            % Create Button_8
            app.Button_8 = uibutton(app.UIFigure, 'push');
            app.Button_8.ButtonPushedFcn = createCallbackFcn(app, @ResetAllSelectionsButtonPushed, true);
            app.Button_8.BackgroundColor = [0.8627 0.8118 0.7529];
            app.Button_8.Position = [35 236 90 30];
            app.Button_8.Text = '重置所有圈选';

            % Create Label_6
            app.Label_6 = uilabel(app.UIFigure);
            app.Label_6.HorizontalAlignment = 'center';
            app.Label_6.FontWeight = 'bold';
            app.Label_6.Position = [36 164 53 22];
            app.Label_6.Text = '权重设置';

            % Create Slider
            app.Slider = uislider(app.UIFigure);
            app.Slider.Limits = [0 8];
            app.Slider.MajorTicks = [0 1 2 3 4 5 6 7 8];
            app.setIfSupported(app.Slider, 'MajorTickLabels', {'0', '1', '2', '3', '4', '5', '6', '7', '8'});
            app.Slider.ValueChangedFcn = createCallbackFcn(app, @SliderValueChanged, true);
            app.Slider.MinorTicks = [];
            app.Slider.Position = [113 178 150 3];
            app.Slider.Value = 1;

            % Create Label_7
            app.Label_7 = uilabel(app.UIFigure);
            app.Label_7.HorizontalAlignment = 'center';
            app.Label_7.FontWeight = 'bold';
            app.Label_7.Position = [102 115 25 35];
            app.Label_7.Text = '红';

            % Create Label_8
            app.Label_8 = uilabel(app.UIFigure);
            app.Label_8.HorizontalAlignment = 'center';
            app.Label_8.FontWeight = 'bold';
            app.Label_8.Position = [137 115 25 35];
            app.Label_8.Text = '粉';

            % Create Label_9
            app.Label_9 = uilabel(app.UIFigure);
            app.Label_9.HorizontalAlignment = 'center';
            app.Label_9.FontWeight = 'bold';
            app.Label_9.Position = [157 115 25 35];
            app.Label_9.Text = '橙';

            % Create Label_10
            app.Label_10 = uilabel(app.UIFigure);
            app.Label_10.HorizontalAlignment = 'center';
            app.Label_10.FontWeight = 'bold';
            app.Label_10.Position = [176 115 25 35];
            app.Label_10.Text = '黄';

            % Create Label_11
            app.Label_11 = uilabel(app.UIFigure);
            app.Label_11.HorizontalAlignment = 'center';
            app.Label_11.FontWeight = 'bold';
            app.Label_11.Position = [195 115 25 35];
            app.Label_11.Text = '绿';

            % Create Label_12
            app.Label_12 = uilabel(app.UIFigure);
            app.Label_12.HorizontalAlignment = 'center';
            app.Label_12.FontWeight = 'bold';
            app.Label_12.Position = [214 115 25 35];
            app.Label_12.Text = '青';

            % Create Label_13
            app.Label_13 = uilabel(app.UIFigure);
            app.Label_13.HorizontalAlignment = 'center';
            app.Label_13.FontWeight = 'bold';
            app.Label_13.Position = [233 115 25 35];
            app.Label_13.Text = '蓝';

            % Create Label_14
            app.Label_14 = uilabel(app.UIFigure);
            app.Label_14.HorizontalAlignment = 'center';
            app.Label_14.FontWeight = 'bold';
            app.Label_14.Position = [251 115 25 35];
            app.Label_14.Text = '紫';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = MeterWeightSetting_V4_Compatibility

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end