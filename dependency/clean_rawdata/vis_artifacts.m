% vis_artifacts(NewEEG,OldEEG,Options...)
% Display the artifact rejections done by any of the artifact cleaning functions.
%
% Keyboard Shortcuts:
%   [n] : display just the new time series
%   [o] : display just the old time series
%   [b] : display both time series super-imposed
%   [d] : display the difference between both time series
%   [+] : increase signal scale
%   [-] : decrease signal scale
%   [*] : expand time range
%   [/] : reduce time range
%   [h] : show/hide slider
%
% In:
%   NewEEG     : cleaned continuous EEG data set
%   OldEEG     : original continuous EEG data set
%   Options... : name-value pairs specifying the options, with names:
%                'YRange' : y range of the figure that is occupied by the signal plot
%                'YScaling' : distance of the channel time series from each other in std. deviations
%                'WindowLength : window length to display
%                'NewColor' : color of the new (i.e., cleaned) data
%                'OldColor' : color of the old (i.e., uncleaned) data
%                'HighpassOldData' : whether to high-pass the old data if not already done
%                'ScaleBy' : the data set according to which the display should be scaled, can be 
%                            'old' or 'new' (default: 'new')
%                'ChannelSubset' : optionally a channel subset to display
%                'TimeSubet' : optionally a time subrange to display
%                'DisplayMode' : what should be displayed: 'both', 'new', 'old', 'diff'
%                'ShowSetname' : whether to display the dataset name in the title
%                'EqualizeChannelScaling' : optionally equalize the channel scaling
%
% Examples:
%  vis_artifacts(clean,raw)
%
%  % display only a subset of channels
%  vis_artifacts(clean,raw,'ChannelSubset',1:4:raw.nbchan);

% Author: Christian Kothe and Makoto Miyakoshi, SCCN,INC,UCSD 2013
% History:
% 06/26/2013 ver 1.1 by Makoto. Included in an EEGLAB plugin. Shows keyboard shortcut in the plot.
% 09/04/2012 ver 1.0 by Christian. Created.

function [h_old,h_new] = vis_artifacts(new,old,varargin)


done_legend = false;

if nargin < 2
    old = new; end

% parse options
opts = hlp_varargin2struct(varargin, ...
    {'yrange','YRange'}, [0.05 0.95], ...       % y range of the figure occupied by the signal plot
    {'yscaling','YScaling'}, 3.5, ...           % distance of the channel time series from each other in std. deviations
    {'wndlen','WindowLength'}, 10, ...          % window length to display
    {'newcol','NewColor'}, [0 0 0.5], ...       % color of the new (i.e., cleaned) data
    {'oldcol','OldColor'}, [1 0 0], ...         % color of the old (i.e., uncleaned) data
    {'highpass_old','HighpassOldData'},true, ...% whether to high-pass the old data if not already done
    {'scale_by','ScaleBy'},'new',...            % the data set according to which the display should be scaled
    {'channel_subset','ChannelSubset'},[], ...  % optionally a channel subset to display
    {'time_subset','TimeSubset'},[],...         % optionally a time subrange to display
    {'display_mode','DisplayMode'},'both',...   % what should be displayed: 'both', 'new', 'old', 'diff'
    {'show_setname','ShowSetname'},true,...     % whether to display the dataset name in the title
    {'line_spec','LineSpec'},'-',...            % line style for plotting
    {'line_width','LineWidth'},0.5,...          % line width
    {'add_legend','AddLegend'},false,...         % add a legend
    {'equalize_channel_scaling','EqualizeChannelScaling'},false);  % optionally equalize the channel scaling

% ensure that the data are not epoched and expand the rejections with NaN's (now both should have the same size)
new = expand_rejections(to_continuous(new));
old = expand_rejections(to_continuous(old));
new.chanlocs = old.chanlocs;

% make sure that the old data is high-passed the same way as the new data
if opts.highpass_old && isfield(new.etc,'clean_drifts_kernel') && ~isfield(old.etc,'clean_drifts_kernel')
    old.data = old.data';
    for c=1:old.nbchan
        old.data(:,c) = filtfilt_fast(new.etc.clean_drifts_kernel,1,old.data(:,c)); end
    old.data = old.data';
end

if isscalar(opts.line_width)
    opts.line_width = [opts.line_width opts.line_width]; end

% optionally pick a subrange to work on
if ~isempty(opts.channel_subset)
    old = pop_select(old,'channel',opts.channel_subset);
    new = pop_select(new,'channel',opts.channel_subset);
end

if ~isempty(opts.time_subset)
    old = pop_select(old,'time',opts.time_subset);
    new = pop_select(new,'time',opts.time_subset);
end

if opts.equalize_channel_scaling    
    rescale = 1./mad(old.data,[],2);
    new.data = bsxfun(@times,new.data,rescale);
    old.data = bsxfun(@times,old.data,rescale);
end

% create a unique name for this visualization and store the options it in the workspace
taken = evalin('base','whos(''vis_*'')');
visname = genvarname('vis_artifacts_opts',{taken.name});
visinfo.opts = opts;
assignin('base',visname,visinfo);

% create figure & slider
lastPos = 0;
hFig = figure('ResizeFcn',@on_window_resized,'KeyPressFcn',@(varargin)on_key(varargin{2}.Key)); hold; axis();
hAxis = gca;
hSlider = uicontrol('style','slider','KeyPressFcn',@(varargin)on_key(varargin{2}.Key)); on_resize();
jSlider = findjobj(hSlider);
jSlider.AdjustmentValueChangedCallback = @on_update;

annotation(gcf,'textbox', [0 0.07 1 0],...
    'String', {'Keyboard shortcuts: [n] new data, [o] old data, [b] both data, [d] difference, [+] increase amp scale, [-] decrease amp scale, [*] expand time scale, [/] shrink time scale, [h] show/hide slider.'},...
    'HorizontalAlignment','center', 'FontSize',14, 'FitBoxToText','off', 'LineStyle','none');   

% do the initial update
on_update();


    function repaint(relPos,moved)
        % repaint the current data
        
        % if this happens, we are maxing out MATLAB's graphics pipeline: let it catch up
        if relPos == lastPos && moved
            return; end
        
        % get potentially updated options
        visinfo = evalin('base',visname);
        
        % title

        % axes
        cla;
        
        % compute pixel range from axis properties
        xl = get(hAxis,'XLim');
        yl = get(hAxis,'YLim');
        fp = get(hFig,'Position');
        ap = get(hAxis,'Position');
        pixels = (fp(3))*(ap(3)-ap(1));
        ylr = yl(1) + opts.yrange*(yl(2)-yl(1));
        channel_y = (ylr(2):(ylr(1)-ylr(2))/(size(new.data,1)-1):ylr(1))';
        
        % compute sample range
        wndsamples = visinfo.opts.wndlen * new.srate;
        pos = floor((size(new.data,2)-wndsamples)*relPos);
        wndindices = 1 + floor(0:wndsamples/pixels:(wndsamples-1));

        oldwnd = old.data(:,pos+wndindices);
        newwnd = new.data(:,pos+wndindices);
        if strcmp(opts.scale_by,'old')
            iqrange = iqr(oldwnd')';
        else
            iqrange = iqr(newwnd')';
            iqrange(isnan(iqrange)) = iqr(oldwnd(isnan(iqrange),:)')';
        end
        scale = ((ylr(2)-ylr(1))/size(new.data,1)) ./ (visinfo.opts.yscaling*iqrange); scale(~isfinite(scale)) = 0;
        scale(scale>median(scale)*3) = median(scale);
        scale = repmat(scale,1,length(wndindices));
                
        % draw
        if opts.show_setname
            tit = sprintf('%s - ',[old.filepath filesep old.filename]);
        else
            tit = '';
        end
        tit = [tit sprintf('[%.1f - %.1f]',new.xmax*relPos, new.xmax*relPos + opts.wndlen)];
        
        switch visinfo.opts.display_mode            
            case 'both'                
                title([tit '; superposition'],'Interpreter','none');
                h_old = plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*oldwnd)','Color',opts.oldcol,'LineWidth',opts.line_width(1));
                h_new = plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*newwnd)','Color',opts.newcol,'LineWidth',opts.line_width(2));
            case 'new'
                title([tit '; cleaned'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*newwnd)','Color',opts.newcol,'LineWidth',opts.line_width(2));
            case 'old'
                title([tit '; original'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*oldwnd)','Color',opts.oldcol,'LineWidth',opts.line_width(1));
            case 'diff'
                title([tit '; difference'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*(oldwnd-newwnd))','Color',opts.newcol,'LineWidth',opts.line_width(1));
        end
        axis([0 1 0 1]);
        
        if opts.add_legend && ~done_legend
            legend([h_old(1);h_new(1)],'Original','Corrected');
            done_legend = 1;
        end
        drawnow;


        lastPos = relPos;
    end


    function on_update(varargin)
        % slider moved
        repaint(get(hSlider,'Value'),~isempty(varargin));
    end

    function on_resize(varargin)
        % adapt/set the slider's size
        wPos = get(hFig,'Position');
        if ~isempty(hSlider)
            try
                set(hSlider,'Position',[20,20,wPos(3)-40,20]);
            catch,end
            on_update;
        end
    end

    function on_window_resized(varargin)
        % window resized
        on_resize();
    end

    function EEG = to_continuous(EEG)
        % convert an EEG set to continuous if currently epoched
        if ndims(EEG.data) == 3
            EEG.data = EEG.data(:,:);
            [EEG.nbchan,EEG.pnts,EEG.trials] = size(EEG.data);
        end
    end

    function EEG = expand_rejections(EEG)
        % reformat the new data so that it can be super-imposed with the old data
        if ~isfield(EEG.etc,'clean_channel_mask')
            EEG.etc.clean_channel_mask = true(1,EEG.nbchan); end
        if ~isfield(EEG.etc,'clean_sample_mask')
            EEG.etc.clean_sample_mask = true(1,EEG.pnts); end
        tmpdata = nan(length(EEG.etc.clean_channel_mask),length(EEG.etc.clean_sample_mask));
        tmpdata(EEG.etc.clean_channel_mask,EEG.etc.clean_sample_mask) = EEG.data;
        EEG.data = tmpdata;
        [EEG.nbchan,EEG.pnts] = size(EEG.data);
    end

    function on_key(key)
        visinfo = evalin('base',visname);
        switch lower(key)
            case '+'
                % decrease datascale
                visinfo.opts.yscaling = visinfo.opts.yscaling*0.9;
            case '-'
                % increase datascale
                visinfo.opts.yscaling = visinfo.opts.yscaling*1.1;
            case '*'
                % increase timerange
                visinfo.opts.wndlen = visinfo.opts.wndlen*1.1;                
            case '/'
                % decrease timerange
                visinfo.opts.wndlen = visinfo.opts.wndlen*0.9;                
            case 'pagedown'
                % shift display page offset down
                visinfo.opts.pageoffset = visinfo.opts.pageoffset+1;                
            case 'pageup'
                % shift display page offset up
                visinfo.opts.pageoffset = visinfo.opts.pageoffset-1;
            case 'n'
                visinfo.opts.display_mode = 'new';
            case 'o'
                visinfo.opts.display_mode = 'old';
            case 'b'
                visinfo.opts.display_mode = 'both';
            case 'd'
                visinfo.opts.display_mode = 'diff';
            case 'h'
                if strcmp(get(hSlider,'Visible'),'on')
                    set(hSlider,'Visible','off')
                else
                    set(hSlider,'Visible','on')
                end
        end        
        assignin('base',visname,visinfo);
        on_update();
    end

end


function res = hlp_varargin2struct(args, varargin)
% Convert a list of name-value pairs into a struct with values assigned to names.
% struct = hlp_varargin2struct(Varargin, Defaults)
%
% In:
%   Varargin : cell array of name-value pairs and/or structs (with values assigned to names)
%
%   Defaults : optional list of name-value pairs, encoding defaults; multiple alternative names may 
%              be specified in a cell array
%
% Example:
%   function myfunc(x,y,z,varargin)
%   % parse options, and give defaults for some of them: 
%   options = hlp_varargin2struct(varargin, 'somearg',10, 'anotherarg',{1 2 3}); 
%
% Notes:
%   * mandatory args can be expressed by specifying them as ..., 'myparam',mandatory, ... in the defaults
%     an error is raised when any of those is left unspecified
%
%   * the following two parameter lists are equivalent (note that the struct is specified where a name would be expected, 
%     and that it replaces the entire name-value pair):
%     ..., 'xyz',5, 'a',[], 'test','toast', 'xxx',{1}. ...
%     ..., 'xyz',5, struct( 'a',{[]},'test',{'toast'} ), 'xxx',{1}, ...     
%
%   * names with dots are allowed, i.e.: ..., 'abc',5, 'xxx.a',10, 'xxx.yyy',20, ...
%
%   * some parameters may have multiple alternative names, which shall be remapped to the 
%     standard name within opts; alternative names are given together with the defaults,
%     by specifying a cell array of names instead of the name in the defaults, as in the following example:
%     ... ,{'standard_name','alt_name_x','alt_name_y'}, 20, ...
%
% Out: 
%   Result : a struct with fields corresponding to the passed arguments (plus the defaults that were
%            not overridden); if the caller function does not retrieve the struct, the variables are
%            instead copied into the caller's workspace.
%
% Examples:
%   % define a function which takes some of its arguments as name-value pairs
%   function myfunction(myarg1,myarg2,varargin)
%   opts = hlp_varargin2struct(varargin, 'myarg3',10, 'myarg4',1001, 'myarg5','test');
%
%   % as before, but this time allow an alternative name for myarg3
%   function myfunction(myarg1,myarg2,varargin)
%   opts = hlp_varargin2struct(varargin, {'myarg3','legacyargXY'},10, 'myarg4',1001, 'myarg5','test');
%
%   % as before, but this time do not return arguments in a struct, but assign them directly to the
%   % function's workspace
%   function myfunction(myarg1,myarg2,varargin)
%   hlp_varargin2struct(varargin, {'myarg3','legacyargXY'},10, 'myarg4',1001, 'myarg5','test');
%
% See also:
%   hlp_struct2varargin, arg_define
%
%                               Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                               2010-04-05

% a struct was specified as first argument
if isstruct(args)
    args = {args}; end

% --- handle defaults ---
if ~isempty(varargin)
    % splice substructs into the name-value list
    if any(cellfun('isclass',varargin(1:2:end),'struct'))
        varargin = flatten_structs(varargin); end    
    
    defnames = varargin(1:2:end);
    defvalues = varargin(2:2:end);
    
    % make a remapping table for alternative default names...
    for k=find(cellfun('isclass',defnames,'cell'))
        for l=2:length(defnames{k})
                name_for_alternative.(defnames{k}{l}) = defnames{k}{1}; end
        defnames{k} = defnames{k}{1};
    end
    
    % create default struct
    if [defnames{:}]~='.'
        % use only the last assignment for each name
        [s,indices] = sort(defnames(:)); 
        indices( strcmp(s((1:end-1)'),s((2:end)'))) = [];
        % and make the struct
        res = cell2struct(defvalues(indices),defnames(indices),2);
    else
        % some dot-assignments are contained in the defaults
        try
            res = struct();
            for k=1:length(defnames)
                if any(defnames{k}=='.')
                    eval(['res.' defnames{k} ' = defvalues{k};']);
                else
                    res.(defnames{k}) = defvalues{k};
                end
            end
        catch
            error(['invalid field name specified in defaults: ' defnames{k}]);
        end
    end
else
    res = struct();
end

% --- handle overrides ---
if ~isempty(args)
    % splice substructs into the name-value list
    if any(cellfun('isclass',args(1:2:end),'struct'))
        args = flatten_structs(args); end
    
    % rewrite alternative names into their standard form...
    if exist('name_for_alternative','var')
        for k=1:2:length(args)
            if isfield(name_for_alternative,args{k})
                args{k} = name_for_alternative.(args{k}); end
        end
    end
    
    % override defaults with arguments...
    try
        if [args{1:2:end}]~='.'
            for k=1:2:length(args)
                res.(args{k}) = args{k+1}; end
        else
            % some dot-assignments are contained in the overrides
            for k=1:2:length(args)
                if any(args{k}=='.')
                    eval(['res.' args{k} ' = args{k+1};']);
                else
                    res.(args{k}) = args{k+1};
                end
            end
        end
    catch
        if ischar(args{k})
            error(['invalid field name specified in arguments: ' args{k}]);
        else
            error(['invalid field name specified for the argument at position ' num2str(k)]);
        end
    end
end

% check for missing but mandatory args
% note: the used string needs to match mandatory.m
missing_entries = strcmp('__arg_mandatory__',struct2cell(res)); 
if any(missing_entries)
    fn = fieldnames(res)';
    fn = fn(missing_entries);
    error(['The parameters {' sprintf('%s, ',fn{1:end-1}) fn{end} '} were unspecified but are mandatory.']);
end

% copy to the caller's workspace if no output requested
if nargout == 0
    for fn=fieldnames(res)'
        assignin('caller',fn{1},res.(fn{1})); end
end
end

% substitute any structs in place of a name-value pair into the name-value list
function args = flatten_structs(args)
k = 1;
while k <= length(args)
    if isstruct(args{k})
        tmp = [fieldnames(args{k}) struct2cell(args{k})]';
        args = [args(1:k-1) tmp(:)' args(k+1:end)];
        k = k+numel(tmp);
    else
        k = k+2;
    end
end
end

function X = filtfilt_fast(varargin)
% Like filtfilt(), but faster when filter and signal are long (and A=1).
% Y = filtfilt_fast(B,A,X)
%
% Uses FFT convolution (needs fftfilt). The function is faster than filter when approx. length(B)>256 and size(X,Dim)>1024, 
% otherwise slower (due size-testing overhead).
%
% Note:
%  Can also be called with four arguments, as Y = filtfilt_fast(N,F,A,X), 
%  in which case an Nth order FIR filter is designed that has the desired frequency response A at normalized frequencies F;
%  F must be 0<=F<=1, and must be 0 and 1 at its both ends, respectively. The function fir2 is used for frequency-sampling filter design.
%
% See also: 
%   filtfilt, filter
% 
%                           Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                           2010-07-14

if nargin == 3
    [B A X] = deal(varargin{:});
elseif nargin == 4
    [N F M X] = deal(varargin{:});
    B = fir2(N,F,sqrt(M)); A = 1;
else
    help filtfilt_fast;
    return;
end

if A == 1
    was_single = strcmp(class(X),'single');
    w = length(B); t = size(X,1);    
    % extrapolate
    X = double([bsxfun(@minus,2*X(1,:),X((w+1):-1:2,:)); X; bsxfun(@minus,2*X(t,:),X((t-1):-1:t-w,:))]);
    % filter, reverse
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    % filter, reverse
    X = filter_fast(B,A,X); X = X(length(X):-1:1,:);
    % remove extrapolated pieces
    X([1:w t+w+(1:w)],:) = [];
    if was_single
        X = single(X); end    
else    
    % fall back to filtfilt for the IIR case
    X = filtfilt(B,A,X);
end
end



function [X,Zf] = filter_fast(B,A,X,Zi,dim)
% Like filter(), but faster when both the filter and the signal are long.
% [Y,Zf] = filter_fast(B,A,X,Zi,Dim)
%
% Uses FFT convolution (needs fftfilt). The function is faster than filter when approx. length(B)>256 and size(X,Dim)>1024,
% otherwise slower (due size-testing overhead).
%
% See also:
%   filter, fftfilt
%
%                           Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                           2010-07-09

persistent has_fftfilt;
if isempty(has_fftfilt)
    has_fftfilt = exist('fftfilt','file');
    % see if we also have the license...
    try
        x=fftfilt();
    catch e
        if strcmp(e.identifier,'MATLAB:UndefinedFunction')
            has_fftfilt = false; end
    end
end

if nargin <= 4
    dim = find(size(X)~=1,1); end
if nargin <= 3
    Zi = []; end

lenx = size(X,dim);
lenb = length(B);
if lenx == 0
    % empty X
    Zf = Zi;
elseif lenb < 256 || lenx<1024 || lenx <= lenb || lenx*lenb < 4000000 || ~isequal(A,1) || ~has_fftfilt
    % use the regular filter
    if nargout > 1
        [X,Zf] = filter(B,A,X,Zi,dim);
    else
        X = filter(B,A,X,Zi,dim);
    end
else
    was_single = strcmp(class(X),'single');
    % fftfilt can be used
    if isempty(Zi)
        % no initial conditions to take care of
        if nargout < 2
            % and no final ones
            X = unflip(fftfilt(B,flip(double(X),dim)),dim);
        else
            % final conditions needed
            X = flip(X,dim);
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
            X = fftfilt(B,double(X));
            X = unflip(X,dim);
        end
    else
        % initial conditions available
        X = flip(X,dim);
        % get a Zi-informed piece
        tmp = filter(B,1,X(1:length(B),:),Zi,1);
        if nargout > 1
            % also need final conditions
            [dummy,Zf] = filter(B,1,X(end-length(B)+1:end,:),Zi,1); %#ok<ASGLU>
        end
        X = fftfilt(B,double(X));
        % incorporate the piece
        X(1:length(B),:) = tmp;
        X = unflip(X,dim);
    end
    if was_single
        X = single(X); end
end
end

function X = flip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = permute(X,order);
end
end

function X = unflip(X,dim)
if dim ~= 1
    order = 1:ndims(X);
    order = order([dim 1]);
    X = ipermute(X,order);
end
end