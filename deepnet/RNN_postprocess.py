import PoseTools
import multiResData
import tensorflow as tf
import PoseUNet_resnet
import os
import h5py
import numpy as np
import movies
from scipy import io as sio
from multiResData import int64_feature, float_feature, bytes_feature
import pickle
import sys
import time
import json
import math
from APT_interface import convert_to_orig


def print_train_data(cur_dict):
    p_str = ''
    for k in cur_dict.keys():
        p_str += '{:s}:{:.2f} '.format(k, cur_dict[k])
    print(p_str)


class RNN_pp(object):


    def __init__(self, conf, mdn_name, name ='rnn_pp', data_name='rnn_pp'):

        self.conf = conf
        self.mdn_name = mdn_name
        self.rnn_pp_hist = 64
        self.train_rep = 10
        self.conf.check_bounds_distort = False
        self.ckpt_file = os.path.join( conf.cachedir, conf.expname + '_' + name + '_ckpt')
        self.name = name
        self.data_name = data_name
        self.ph = {}
        self.fd = {}
        self.net_type = 'rnn'
        self.locs_coords = 'self'
        # self implies the predictions from MDN/UNet will be in the cropped patches location.
        # example implies the predictions will be in the last frame i.e., examples coordinates

    def create_db(self, split_file=None):
        assert  self.rnn_pp_hist % self.conf.batch_size == 0, 'make sure the history is a multiple of batch size'
        assert len(self.conf.mdn_groups)==1, 'This works only for single group. check for line 118'
        net = PoseUNet_resnet.PoseUMDN_resnet(self.conf,self.mdn_name)
        sess, _ = net.restore_net_common(net.create_network)

        conf = self.conf
        on_gt = False
        db_files = ()
        if split_file is not None:
            self.conf.splitType = 'predefined'
            predefined = PoseTools.json_load(split_file)
            split = True
        else:
            predefined = None
            split = False

        mov_split = None

        local_dirs, _ = multiResData.find_local_dirs(conf, on_gt=False)
        lbl = h5py.File(conf.labelfile, 'r')
        view = conf.view
        flipud = conf.flipud
        npts_per_view = np.array(lbl['cfg']['NumLabelPoints'])[0, 0]
        sel_pts = int(view * npts_per_view) + conf.selpts

        out_fns = [True, False]
        data = [[],[]]
        count = 0
        for ndx, dir_name in enumerate(local_dirs):

            cur_pts = multiResData.trx_pts(lbl, ndx, on_gt)
            crop_loc = PoseTools.get_crop_loc(lbl, ndx, view, on_gt)
            cap = movies.Movie(dir_name)

            if conf.has_trx_file:
                trx_files = multiResData.get_trx_files(lbl, local_dirs, on_gt)
                trx = sio.loadmat(trx_files[ndx])['trx'][0]
                n_trx = len(trx)
                trx_split = np.random.random(n_trx) < conf.valratio
                first_frames = np.array( [x['firstframe'][0, 0] for x in trx]) - 1  # for converting from 1 indexing to 0 indexing
                end_frames = np.array( [x['endframe'][0, 0] for x in trx]) - 1  # for converting from 1 indexing to 0 indexing
            else:
                trx = [None]
                n_trx = 1
                trx_split = None
                cur_pts = cur_pts[np.newaxis, ...]

            for trx_ndx in range(n_trx):

                frames = multiResData.get_labeled_frames(lbl, ndx, trx_ndx, on_gt)
                cur_trx = trx[trx_ndx]
                for fnum in frames:
                    info = [ndx, fnum, trx_ndx]
                    cur_out = multiResData.get_cur_env(out_fns, split, conf, info, mov_split, trx_split=trx_split, predefined=predefined)
                    num_rep = 1 + cur_out*(self.train_rep-1)

                    for rep in range(num_rep):
                        cur_pred = np.ones([self.rnn_pp_hist*2,self.conf.n_classes,2])
                        cur_ims = []
                        cur_labels = []
                        raw_preds = []
                        for fndx in range(-self.rnn_pp_hist,self.rnn_pp_hist):
                            frame_in, cur_loc = multiResData.get_patch(
                                cap, fnum, conf, cur_pts[trx_ndx, fnum, :, sel_pts],
                                cur_trx=cur_trx, flipud=flipud, crop_loc=crop_loc, offset=fndx)
                            cur_labels.append(cur_loc)
                            cur_ims.append(frame_in)

                        cur_ims = np.array(cur_ims)
                        cur_labels = np.array(cur_labels)

                        cur_ims, cur_labels = PoseTools.preprocess_ims(
                            cur_ims, cur_labels, conf, distort=cur_out,scale= self.conf.rescale,
                            group_sz=self.rnn_pp_hist)

                        bsize = self.conf.batch_size
                        nbatches = self.rnn_pp_hist/bsize*2
                        for bndx in range(nbatches):
                            start = bndx*bsize
                            end = (bndx+1)*bsize
                            net.fd[net.inputs[0]] = cur_ims[start:end,...]
                            net.fd[net.inputs[1]] = cur_labels[start:end,...]
                            info_fd = np.zeros([bsize,3])
                            info_fd[:,0] = ndx; info_fd[:,1] = np.arange(start,end); info_fd[:,2] = trx_ndx
                            net.fd[net.inputs[2]] = info_fd
                            net.fd[net.inputs[3]] = np.zeros(net.inputs[3]._shape_as_list())

                            cur_m, cur_s, cur_w = sess.run(net.pred, net.fd)
                            cur_w = cur_w[:,:,0]
                            cur_m = cur_m * net.offset
                            nx = np.argmax(cur_w, axis=1)
                            raw_preds.append(np.array([cur_m[x,nx[x],...] for x in range(cur_m.shape[0])]))

                            hsz = [float(self.conf.imsz[1])/2,float(self.conf.imsz[0])/2]
                            if self.locs_coords == 'example' and conf.has_trx_file:
                                for e_ndx in range(bsize):
                                    trx_fnum = fnum - first_frames[trx_ndx]
                                    trx_fnum_ex = fnum - first_frames[trx_ndx] \
                                        + e_ndx + start - self.rnn_pp_hist
                                    trx_fnum_ex = trx_fnum_ex if trx_fnum_ex >0 else 0
                                    trx_fnum_ex = trx_fnum_ex if trx_fnum_ex < end_frames[trx_ndx] else end_frames[trx_ndx]
                                    temp_pred = cur_m[e_ndx,nx[e_ndx],:,:]
                                    dx = cur_trx['x'][0, trx_fnum] - cur_trx['x'][0, trx_fnum_ex]
                                    dy = cur_trx['y'][0, trx_fnum] - cur_trx['y'][0, trx_fnum_ex]
                                    # -1 for 1-indexing in matlab and 0-indexing in python
                                    tt = cur_trx['theta'][0, trx_fnum] - cur_trx['theta'][0, trx_fnum_ex]
                                    R = [[np.cos(tt), -np.sin(tt)], [np.sin(tt), np.cos(tt)]]
                                    rr = (cur_trx['theta'][0, trx_fnum]) + math.pi / 2
                                    Q = [[np.cos(rr), -np.sin(rr)], [np.sin(rr), np.cos(rr)]]
                                    curlocs = np.dot(temp_pred - hsz, R) + hsz - np.dot([dx, dy], Q)
                                    cur_pred[start+e_ndx, ...] = curlocs
                            else:
                                cur_pred[start:end,:,:] = cur_m[np.arange(bsize),nx,:,:]

                        # ---------- Code for testing
                        # raw_pred = np.array(raw_preds).reshape((cur_pred.shape[0],) + raw_preds[0].shape[1:])
                        # f, ax = plt.subplots(2, 2)
                        # ax = ax.flatten()
                        # ex = 32
                        # xx = multiResData.get_patch(cap, fnum, conf, cur_pts[trx_ndx, fnum, :, sel_pts],
                        #                             cur_trx=cur_trx, crop_loc=None, offset=ex, stationary=False)
                        # ax[0].imshow(xx[0][:, :, 0], 'gray')
                        # ax[0].scatter(cur_pred[-self.rnn_pp_hist + ex, :, 0], cur_pred[-self.rnn_pp_hist + ex, :, 1])
                        # xx = multiResData.get_patch(cap, fnum, conf, cur_pts[trx_ndx, fnum, :, sel_pts],
                        #                             cur_trx=cur_trx, crop_loc=None, offset=0, stationary=False)
                        # ax[1].imshow(xx[0][:, :, 0], 'gray')
                        # ax[1].scatter(cur_pred[self.rnn_pp_hist, :, 0], cur_pred[self.rnn_pp_hist, :, 1])
                        # ax[2].imshow(cur_ims[-self.rnn_pp_hist + ex, :, :, 0], 'gray')
                        # ax[2].scatter(raw_pred[-self.rnn_pp_hist + ex, :, 0], raw_pred[-self.rnn_pp_hist + ex, :, 1])
                        # ax[3].imshow(cur_ims[self.rnn_pp_hist, :, :, 0], 'gray')
                        # ax[3].scatter(raw_pred[self.rnn_pp_hist, :, 0], raw_pred[self.rnn_pp_hist, :, 1])

                        # ---------- Code for testing II
                        # zz = np.diff(cur_pred, axis=0)
                        # rx = self.rnn_pp_hist
                        # dd = np.sqrt(np.sum((cur_pred[rx, ...] - cur_labels[rx, ...]) ** 2, axis=-1))
                        # print dd.max(), dd.argmax()
                        # ix = dd.argmax()
                        # n_ex = 3
                        # f, ax = plt.subplots(2, 4 + n_ex, figsize=(18, 12))
                        # ax = ax.T.flatten()
                        # ax[0].plot(cur_pred[:, ix, 0], cur_pred[:, ix, 1])
                        # ax[1].plot(zz[:, ix, 0], zz[:, ix, 1])
                        # ax[2].plot(zz[:, ix, 0])
                        # ax[3].plot(zz[:, ix, 1])
                        # ax[4].imshow(cur_ims[..., 0].mean(axis=0), 'gray')
                        # ax[5].imshow(cur_ims[..., 0].min(axis=0), 'gray')
                        # ax[6].imshow(cur_ims[self.rnn_pp_hist, ..., 0], 'gray')
                        # ax[6].scatter(cur_pred[self.rnn_pp_hist, :, 0], cur_pred[self.rnn_pp_hist, :, 1])
                        # ax[7].imshow(cur_ims[self.rnn_pp_hist, ..., 0], 'gray')
                        # ax[7].scatter(cur_labels[self.rnn_pp_hist, :, 0], cur_labels[self.rnn_pp_hist, :, 1])
                        # plt.title('{}'.format(ix))
                        # for xx in range(2 * n_ex):
                        #     xxi = multiResData.get_patch(cap, fnum, conf, cur_pts[trx_ndx, fnum, :, sel_pts],
                        #                                  cur_trx=cur_trx, crop_loc=None, offset=-xx, stationary=False)
                        #     ax[8 + xx].imshow(xxi[0][:, :, 0], 'gray')
                        #     ax[8 + xx].scatter(cur_pred[self.rnn_pp_hist - xx, ix, 0],
                        #                        cur_pred[self.rnn_pp_hist - xx, ix, 1])
                        #     if xx is 0:
                        #         ax[8 + xx].scatter(cur_pred[self.rnn_pp_hist - n_ex:, ix, 0],
                        #                            cur_pred[self.rnn_pp_hist - n_ex:, ix, 1])
                        #
                        rx = self.rnn_pp_hist
                        dd = np.sqrt(np.sum((cur_pred[rx, ...] - cur_labels[rx, ...]) ** 2, axis=-1))
                        cur_info = [ndx, fnum, trx_ndx]
                        if cur_out:
                            data[0].append([cur_pred, cur_labels[-1,...], cur_info])
                        else:
                            data[1].append([cur_pred, cur_labels[-1,...], cur_info])
                        count += 1

                    if count % 50 == 0:
                        sys.stdout.write('.')
                        with open(os.path.join(conf.cachedir,self.data_name + '.p'),'w') as f:
                            pickle.dump(data,f)
                    if count % 2000 == 0:
                        sys.stdout.write('\n')

            cap.close()  # close the movie handles

        with open(os.path.join(conf.cachedir,self.data_name + '.p'),'w') as f:
            pickle.dump(data,f)
        lbl.close()



    def get_var_list(self):
        var_list = tf.global_variables()
        return var_list


    def create_saver(self):
        saver = {}
        name = self.name
        saver['out_file'] = os.path.join(
            self.conf.cachedir,
            self.conf.expname + '_' + name)
        saver['train_data_file'] = os.path.join(
                self.conf.cachedir,
                self.conf.expname + '_' + name + '_traindata')
        saver['ckpt_file'] = self.ckpt_file
        var_list = self.get_var_list()
        saver['saver'] = (tf.train.Saver(var_list=var_list,
                                         max_to_keep=self.conf.maxckpt,
                                         save_relative_paths=True))
        self.saver = saver


    def restore(self, sess, model_file=None):
        saver = self.saver
        if model_file is not None:
            latest_model_file = model_file
            saver['saver'].restore(sess, model_file)
        else:
            grr = os.path.split(self.ckpt_file) # angry that get_checkpoint_state doesnt accept complete path to ckpt file. Damn idiots!
            latest_ckpt = tf.train.get_checkpoint_state(grr[0],grr[1])
            latest_model_file = latest_ckpt.model_checkpoint_path
            saver['saver'].restore(sess, latest_model_file)
        return latest_model_file


    def save(self, sess, step):
        saver = self.saver
        out_file = saver['out_file'].replace('\\', '/')
        saver['saver'].save(sess, out_file, global_step=step,
                            latest_filename=os.path.basename(saver['ckpt_file']))
        print('Saved state to %s-%d' % (out_file, step))


    def create_network(self):
        if self.net_type == 'rnn':
            self.create_network_rnn()
        elif self.net_type == 'conv':
            self.create_network_conv()
        elif self.net_type == 'transformer':
            self.create_network_transformer()
        else:
            raise ValueError('incorrect network type')

    def create_network_rnn(self):
        lstm_size = 256
        batch_size = self.conf.batch_size*2

        # in_w = tf.get_variable('in_weights',[self.conf.n_classes*2, lstm_size],initializer=tf.contrib.layers.xavier_initializer())
        # in_b = tf.get_variable('softmax_weights',[lstm_size],initializer=tf.constant_initializer(0.))
        # input = tf.nn.relu(tf.matmul(self.inputs[0], in_w) + in_b)

        input_layer = tf.layers.Dense(lstm_size, activation=tf.nn.relu,
            kernel_initializer=tf.orthogonal_initializer())
        input = input_layer(self.inputs[0])

        # lstm = tf.contrib.rnn.BasicLSTMCell(lstm_size)
        lstm = tf.contrib.rnn.GRUCell(lstm_size)
        # Initial state of the LSTM memory.
        state = lstm.zero_state(batch_size, dtype=tf.float32)
        for cur_ndx in range(self.rnn_pp_hist):
            cur_input = input[:, cur_ndx,:]
            output, state = lstm(cur_input, state)

        # softmax_w = tf.get_variable('softmax_weights',[lstm_size,self.conf.n_classes*2],initializer=tf.contrib.layers.xavier_initializer())
        # softmax_b = tf.get_variable('softmax_weights',[self.conf.n_classes*2],initializer=tf.constant_initializer(0.))
        # out = tf.matmul(output, softmax_w) + softmax_b

        output_layer = tf.layers.Dense(self.conf.n_classes*2, activation=None,
            kernel_initializer=tf.orthogonal_initializer())
        out = output_layer(output)
        loss = tf.nn.l2_loss(out-self.inputs[1])

        self.pred = out
        self.cost = loss

        for k in self.ph.keys():
            self.fd[self.ph[k]] = np.zeros(self.ph[k]._shape_as_list())


    def create_network_conv(self):
        conv_sizes = [256, 256, 256]

        n_in = np.prod(self.inputs[0]._shape_as_list()[1:])
        X = tf.reshape(self.inputs[0], [-1, n_in])
        input = X

        for cur_sz in conv_sizes:
            layer = tf.layers.Dense(cur_sz, activation=tf.nn.relu,
                kernel_initializer=tf.orthogonal_initializer())
            X = layer(X)

        out_layer = tf.layers.Dense(self.conf.n_classes*2, activation=None,
            kernel_initializer=tf.orthogonal_initializer())
        skip_layer = tf.layers.Dense(self.conf.n_classes*2, activation=None,
            kernel_initializer=tf.orthogonal_initializer())
        out = out_layer(X) + skip_layer(input)

        loss = tf.nn.l2_loss(out-self.inputs[1])

        self.pred = out
        self.cost = loss

        for k in self.ph.keys():
            self.fd[self.ph[k]] = np.zeros(self.ph[k]._shape_as_list())


    def create_network_transformer(self):
        import transformer
        from transformer.hbconfig import Config
        xx = transformer.Graph(tf.estimator.ModeKeys.TRAIN)
        Config.data.max_seq_length = self.rnn_pp_hist
        Config.data.n_classes = self.conf.n_classes
        Config.data.target_vocab_size = 2 * self.conf.n_classes
        rr = xx.build(self.inputs[0], self.inputs[0])
        out = rr[0][:,-1,:]
        loss = tf.nn.l2_loss(out-self.inputs[1])
        self.pred = out
        self.cost = loss


    def train_step(self, step, sess, learning_rate, training_iters):
        self.fd_train()
        cur_step = float(step)

        n_steps = self.conf.n_steps
        cur_lr = learning_rate * (self.conf.gamma ** (cur_step * n_steps / training_iters))
        self.fd[self.ph['learning_rate']] = cur_lr
        run_options = tf.RunOptions(report_tensor_allocations_upon_oom=True)
        sess.run(self.opt, self.fd, options=run_options)


    def create_optimizer(self):
        update_ops = tf.get_collection(tf.GraphKeys.UPDATE_OPS)
        with tf.control_dependencies(update_ops):
            optimizer = tf.train.AdamOptimizer(
                learning_rate=self.ph['learning_rate'])
            gradients, variables = zip(*optimizer.compute_gradients(self.cost))
            gradients = [None if gradient is None else
                         tf.clip_by_norm(gradient, 5.0)
                         for gradient in gradients]
            self.opt = optimizer.apply_gradients(zip(gradients, variables))


    def init_td(self):
        ex_td_fields = ['step']
        self.td_fields = ['loss','dist', 'prev']
        for t_f in self.td_fields:
            ex_td_fields.append('train_' + t_f)
            ex_td_fields.append('val_' + t_f)
        train_info = {}
        for t_f in ex_td_fields:
            train_info[t_f] = []
        self.train_info = train_info

    def save_td(self):
        saver = self.saver
        train_data_file = saver['train_data_file']
        with open(train_data_file, 'wb') as td_file:
            pickle.dump([self.train_info, self.conf], td_file, protocol=2)
        json_data = {}
        for x in self.train_info.keys():
            json_data[x] = np.array(self.train_info[x]).astype(np.float64).tolist()
        with open(train_data_file+'.json','w') as json_file:
            json.dump(json_data, json_file)


    def update_td(self, cur_dict):
        for k in cur_dict.keys():
            self.train_info[k].append(cur_dict[k])
        print_train_data(cur_dict)

    def create_datasets(self):
        with open(os.path.join(self.conf.cachedir,'rnn_pp.p'),'r') as f:
            X = pickle.load(f)

        t_labels = np.array([x[1] for x in X[0]]).reshape([-1,self.conf.n_classes*2])
        t_inputs = np.array([x[0] for x in X[0]]).reshape([-1,self.rnn_pp_hist,self.conf.n_classes*2])
        v_labels = np.array([x[1] for x in X[1]]).reshape([-1,self.conf.n_classes*2])
        v_inputs = np.array([x[0] for x in X[1]]).reshape([-1,self.rnn_pp_hist,self.conf.n_classes*2])

        m_sz = max(self.conf.imsz)
        self.t_labels = t_labels/m_sz
        self.t_inputs = t_inputs/m_sz
        self.v_labels = v_labels/m_sz
        self.v_inputs = v_inputs/m_sz

        t_inputs_ph = tf.placeholder(tf.float32, t_inputs.shape)
        t_labels_ph = tf.placeholder(tf.float32, t_labels.shape)
        v_inputs_ph = tf.placeholder(tf.float32, v_inputs.shape)
        v_labels_ph = tf.placeholder(tf.float32, v_labels.shape)

        train_dataset = tf.data.Dataset.from_tensor_slices((t_inputs_ph,t_labels_ph))
        val_dataset = tf.data.Dataset.from_tensor_slices((v_inputs_ph,v_labels_ph))
        train_dataset = train_dataset.repeat()
        val_dataset = val_dataset.repeat()
        train_dataset = train_dataset.shuffle(buffer_size=200)
        val_dataset = val_dataset.shuffle(buffer_size=200)
        train_dataset = train_dataset.batch(self.conf.batch_size*2)
        val_dataset = val_dataset.batch(self.conf.batch_size*2)


        self.train_iterator = train_dataset.make_initializable_iterator()
        self.val_iterator = val_dataset.make_initializable_iterator()

        train_next = self.train_iterator.get_next()
        val_next = self.val_iterator.get_next()

        self.ph['t_inputs_ph'] = t_inputs_ph
        self.ph['t_labels_ph'] = t_labels_ph
        self.ph['v_inputs_ph'] = v_inputs_ph
        self.ph['v_labels_ph'] = v_labels_ph
        self.ph['is_train'] = tf.placeholder(tf.bool,name='is_train')
        self.ph['learning_rate'] = tf.placeholder(tf.float32)

        self.inputs = []
        self.inputs.append(tf.cond(self.ph['is_train'],
                                   lambda: tf.identity(train_next[0]),
                                   lambda: tf.identity(val_next[0])))
        self.inputs.append(tf.cond(self.ph['is_train'],
                                   lambda: tf.identity(train_next[1]),
                                   lambda: tf.identity(val_next[1])))


    def fd_train(self):
        # self.fd[self.ph['phase_train']] = True
        self.fd[self.ph['is_train']] = True

    def fd_val(self):
        # self.fd[self.ph['phase_train']] = False
        self.fd[self.ph['is_train']] = False


    def compute_train_data(self, sess, db_type):
        self.fd_train() if db_type == 'train' \
            else self.fd_val()
        cur_loss, cur_pred, self.cur_inputs = \
            sess.run( [self.cost, self.pred, self.inputs], self.fd)
        cur_dist = self.compute_dist(cur_pred, self.cur_inputs[1])
        prev_dist = self.compute_dist(self.cur_inputs[0][:,-1,...], self.cur_inputs[1])
        return cur_loss, cur_dist, prev_dist


    def compute_dist(self, pred, label):
        m_sz = max(self.conf.imsz)
        pred = pred.reshape([-1,self.conf.n_classes,2])
        label = label.reshape([-1,self.conf.n_classes,2])
        return np.nanmean(np.sqrt(np.sum( (pred-label)**2,axis=-1)))*m_sz


    def train(self):
        self.create_datasets()
        self.create_network()
        self.create_optimizer()
        self.create_saver()
        training_iters = 200000#self.conf.dl_steps
        num_val_rep = self.conf.numTest / self.conf.batch_size + 1
        if self.net_type == 'rnn':
            learning_rate = 0.01
        elif self.net_type == 'conv':
            learning_rate = 0.0001
        else:
            learning_rate = 0.0001

        with tf.Session() as sess:
            sess.run(tf.variables_initializer(self.get_var_list()))
            sess.run(self.train_iterator.initializer,
                     feed_dict={self.ph['t_inputs_ph']: self.t_inputs, self.ph['t_labels_ph']: self.t_labels})
            sess.run(self.val_iterator.initializer,
                     feed_dict={self.ph['v_inputs_ph']: self.v_inputs, self.ph['v_labels_ph']: self.v_labels})
            self.init_td()

            start = time.time()
            for step in range(0, training_iters + 1):
                self.train_step(step, sess, learning_rate, training_iters)
                if step % self.conf.display_step == 0:
                    end = time.time()
                    print('Time required to train: {}'.format(end-start))
                    train_loss, train_dist, train_prev = self.compute_train_data(sess, 'train')
                    val_loss = 0.
                    val_dist = 0.
                    val_prev = 0.
                    for _ in range(num_val_rep):
                        cur_loss, cur_dist, cur_prev = self.compute_train_data(sess, 'val')
                        val_loss += cur_loss
                        val_dist += cur_dist
                        val_prev += cur_prev
                    val_loss = val_loss / num_val_rep
                    val_dist = val_dist / num_val_rep
                    val_prev = val_prev / num_val_rep
                    cur_dict = {'step': step,
                               'train_loss': train_loss, 'val_loss': val_loss,
                               'train_dist': train_dist, 'val_dist': val_dist,
                               'train_prev': train_prev, 'val_prev': val_prev,

                                }
                    self.update_td(cur_dict)
                    start = end
                if step % self.conf.save_step == 0:
                    self.save(sess, step)
                if step % self.conf.save_td_step == 0:
                    self.save_td()
            print("Optimization Finished!")
            self.save(sess, training_iters)
            self.save_td()
        tf.reset_default_graph()


    def create_feed_ph(self):
        self.inputs = []
        bsz = 2*self.conf.batch_size
        self.inputs.append(tf.placeholder(tf.float32,[bsz, self.rnn_pp_hist, self.conf.n_classes*2]) )
        self.inputs.append(tf.placeholder(tf.float32,[bsz, self.conf.n_classes*2]) )
        self.ph['input'] = self.inputs[0]
        self.ph['labels'] = self.inputs[1]


    def classify_val(self, model_file=None):
        self.create_feed_ph()
        self.create_network()
        self.create_saver()

        with open(os.path.join(self.conf.cachedir,self.data_name + '.p'),'r') as f:
            X = pickle.load(f)

        t_labels = np.array([x[1] for x in X[0]]).reshape([-1,self.conf.n_classes*2])
        t_inputs = np.array([x[0] for x in X[0]]).reshape([-1,self.rnn_pp_hist,self.conf.n_classes*2])
        v_labels = np.array([x[1] for x in X[1]]).reshape([-1,self.conf.n_classes*2])
        v_inputs = np.array([x[0] for x in X[1]]).reshape([-1,self.rnn_pp_hist,self.conf.n_classes*2])

        m_sz = max(self.conf.imsz)
        self.t_labels = t_labels/m_sz
        self.t_inputs = t_inputs/m_sz
        self.v_labels = v_labels/m_sz
        self.v_inputs = v_inputs/m_sz

        n_vals = self.v_inputs.shape[0]
        n_batches = n_vals/ self.conf.batch_size/2
        preds = []
        labels = []
        prev_preds = []
        with tf.Session() as sess:
            sess.run(tf.variables_initializer(self.get_var_list()))
            self.restore(sess, model_file=model_file)
            for ndx in range(n_batches):
                cur_s = ndx*self.conf.batch_size*2
                cur_e = (ndx+1)*self.conf.batch_size*2
                cur_in = self.v_inputs[cur_s:cur_e,...]
                cur_label = self.v_labels[cur_s:cur_e,...]
                self.fd[self.ph['input']] = cur_in
                self.fd[self.ph['labels']] = cur_label
                cur_pred = sess.run(self.pred,self.fd)
                labels.append(cur_label)
                preds.append(cur_pred)
                prev_preds.append(cur_in[:,-1,...])

        preds = np.array(preds)
        preds = preds.reshape((-1,) + preds.shape[2:])
        prev_preds = np.array(prev_preds)
        prev_preds = prev_preds.reshape((-1,) + prev_preds.shape[2:])
        labels = np.array(labels)
        labels = labels.reshape((-1,) + labels.shape[2:])
        dd = np.sqrt(np.sum( (preds-labels)**2,axis=-1))

        tf.reset_default_graph()

        return dd, preds, labels
